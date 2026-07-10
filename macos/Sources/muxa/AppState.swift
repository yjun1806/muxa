import Bonsplit
import Foundation
import GhosttyKit
import Observation

/// 앱 전역 상태 + 영속. 워크스페이스(사이드바) ⊃ 프로젝트(상단 탭) ⊃ 터미널 탭(Bonsplit).
/// 프로젝트마다 TerminalStore(Bonsplit 컨트롤러) 하나를 lazy 생성·유지한다.
///
/// 재시작 시 워크스페이스·프로젝트·사이드바 모드 + 프로젝트별 분할 트리가 복원된다.
/// PTY는 프로세스라 복원 불가 → 각 탭은 프로젝트 cwd에서 새 셸로 시작한다.
@MainActor
@Observable
final class AppState {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeId: String = "" // 활성 워크스페이스
    private(set) var sidebarMode: SidebarMode = .expanded

    /// 백그라운드 활동(●)이 있는 프로젝트 id들(A). ProjectTabBar가 관측해 배지를 그린다.
    private(set) var badgedProjects: Set<String> = []

    @ObservationIgnored private let app: ghostty_app_t
    /// 프로젝트 id → TerminalStore. 프로젝트가 독립 분할 레이아웃 하나를 소유한다.
    @ObservationIgnored private var stores: [String: TerminalStore] = [:]
    /// 프로젝트 id → 저장된 분할 트리(재시작 복원용). 아직 안 연 프로젝트 것도 보존한다.
    @ObservationIgnored private var savedLayouts: [String: ExternalTreeNode] = [:]
    /// 프로젝트 id → 저장된 열린 문서/커밋 diff(재시작 복원용).
    @ObservationIgnored private var savedViewers: [String: [SavedViewer]] = [:]

    init(app: ghostty_app_t) {
        self.app = app
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }

    /// 활성 워크스페이스의 활성 프로젝트.
    var activeProject: Project? {
        activeWorkspace?.activeProject
    }

    /// 활성 워크스페이스의 활성 프로젝트 스토어(단축키 대상 — ⌘T/⌘D/⌘W/⌘F).
    var activeStore: TerminalStore? {
        guard let ws = activeWorkspace, let project = ws.activeProject else { return nil }
        return store(for: project, in: ws)
    }

    /// 프로젝트의 터미널 스토어(없으면 생성). cwd는 프로젝트 경로(없으면 워크스페이스 경로 상속).
    func store(for project: Project, in workspace: Workspace) -> TerminalStore {
        if let s = stores[project.id] { return s }
        let cwd = project.path ?? workspace.path
        let s = TerminalStore(app: app, cwd: cwd, restoreTree: savedLayouts[project.id],
                              restoreViewers: savedViewers[project.id] ?? [])
        let pid = project.id
        s.onProjectActivity = { [weak self] in MainActor.assumeIsolated { self?.markProjectBadge(pid) } }
        stores[project.id] = s
        return s
    }

    /// 백그라운드 프로젝트에 활동(●)이 있음을 표시. 지금 보고 있는 활성 프로젝트면 무시.
    private func markProjectBadge(_ projectId: String) {
        guard projectId != activeProject?.id else { return }
        badgedProjects.insert(projectId)
    }

    // MARK: 워크스페이스 액션

    func setActiveId(_ id: String) {
        guard activeId != id else { return }
        activeId = id
        save()
    }

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        save()
    }

    @discardableResult
    func addWorkspace(path: String?) -> Workspace {
        let ws = createWorkspace(path: path)
        workspaces.append(ws)
        activeId = ws.id
        save()
        return ws
    }

    func ensureInitial(path: String?) {
        guard workspaces.isEmpty else { return }
        let ws = createWorkspace(path: path)
        workspaces = [ws]
        activeId = ws.id
        save()
    }

    // MARK: 프로젝트 액션 (활성 워크스페이스 대상)

    /// 활성 워크스페이스에서 프로젝트를 전환한다.
    func setActiveProject(_ projectId: String) {
        badgedProjects.remove(projectId) // 프로젝트를 보게 됐으니 배지 해제
        updateActiveWorkspace { ws in
            guard ws.projects.contains(where: { $0.id == projectId }) else { return ws }
            var next = ws
            next.activeProjectId = projectId
            return next
        }
    }

    /// 새 프로젝트(워크트리 등)를 활성 워크스페이스에 추가하고 활성화한다.
    @discardableResult
    func addProject(name: String, path: String?) -> Project? {
        let project = createProject(name: name, path: path)
        updateActiveWorkspace { ws in
            var next = ws
            next.projects.append(project)
            next.activeProjectId = project.id
            return next
        }
        return activeWorkspace == nil ? nil : project
    }

    /// 활성 워크스페이스에서 프로젝트를 앞/뒤로 순환 전환한다(⌘⇧] / ⌘⇧[).
    func cycleProject(forward: Bool) {
        guard let ws = activeWorkspace, ws.projects.count > 1,
              let idx = ws.projects.firstIndex(where: { $0.id == ws.activeProjectId }) else { return }
        let count = ws.projects.count
        let next = (idx + (forward ? 1 : count - 1)) % count
        setActiveProject(ws.projects[next].id)
    }

    /// 프로젝트를 닫는다(마지막 하나는 남긴다). 활성이면 인접 프로젝트로 전환.
    func closeProject(_ projectId: String) {
        stores[projectId] = nil
        savedLayouts[projectId] = nil
        badgedProjects.remove(projectId)
        updateActiveWorkspace { ws in
            guard ws.projects.count > 1,
                  let idx = ws.projects.firstIndex(where: { $0.id == projectId }) else { return ws }
            var next = ws
            next.projects.remove(at: idx)
            if next.activeProjectId == projectId {
                next.activeProjectId = next.projects[min(idx, next.projects.count - 1)].id
            }
            return next
        }
        // 닫힌 뒤 새로 활성화된 프로젝트도 배지 클리어(사용자가 보게 됐으니) — 유령 배지 방지.
        if let newActive = activeProject?.id { badgedProjects.remove(newActive) }
    }

    /// 활성 워크스페이스를 불변 갱신한다(immutable — 새 배열로 교체).
    private func updateActiveWorkspace(_ transform: (Workspace) -> Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == activeId }) else { return }
        var next = workspaces
        next[idx] = transform(workspaces[idx])
        workspaces = next
        save()
    }

    // MARK: 영속 (메타데이터 + 프로젝트별 분할 트리)

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
        var layouts: [String: ExternalTreeNode]? // 프로젝트 id → 트리. PTY는 복원 안 됨(새 셸).
        var viewers: [String: [SavedViewer]]?    // 프로젝트 id → 열린 문서/커밋 diff.
    }

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.v4.json") // v4: 프로젝트 계층 추가
    }()

    func save() {
        // 인스턴스화된 스토어(=열린 프로젝트)의 현재 분할 트리를 반영한다. 빈 스토어는 스킵.
        for (projectId, store) in stores where !store.controller.allTabIds.isEmpty {
            savedLayouts[projectId] = store.layoutSnapshot() // 트리는 터미널만(뷰어는 아래 목록으로 복원)
            savedViewers[projectId] = store.savedViewers()   // 열린 문서/커밋 diff 목록
        }
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode,
                                 layouts: savedLayouts, viewers: savedViewers)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let snapshot = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        workspaces = snapshot.workspaces
        activeId = snapshot.activeId
        sidebarMode = snapshot.sidebarMode
        savedLayouts = snapshot.layouts ?? [:]
        savedViewers = snapshot.viewers ?? [:]
    }
}

// MARK: - 시스템 경로 (Rust home_dir/current_dir 대체)

enum SystemPaths {
    static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static var currentDir: String? {
        FileManager.default.currentDirectoryPath
    }
}
