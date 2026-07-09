import Bonsplit
import Foundation
import GhosttyKit
import Observation

/// 앱 전역 상태 + 영속. (src/store.ts 이식) 워크스페이스 목록·활성·사이드바 모드를 소유하고,
/// 워크스페이스마다 TerminalStore(Bonsplit 컨트롤러 + 터미널들)를 lazy 생성·유지한다.
///
/// 재시작 시 워크스페이스 목록·cwd·사이드바 모드가 복원된다(분할 레이아웃 복원은 후속).
/// PTY는 프로세스라 복원 불가 → 각 워크스페이스는 초기 터미널 1개로 시작한다.
@MainActor
@Observable
final class AppState {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeId: String = ""
    private(set) var sidebarMode: SidebarMode = .expanded

    @ObservationIgnored private let app: ghostty_app_t
    @ObservationIgnored private var stores: [String: TerminalStore] = [:]
    /// 워크스페이스별 저장된 분할 트리(재시작 복원용). 아직 안 연 워크스페이스 것도 보존한다.
    @ObservationIgnored private var savedLayouts: [String: ExternalTreeNode] = [:]

    init(app: ghostty_app_t) {
        self.app = app
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }

    /// 워크스페이스의 터미널 스토어(없으면 생성). 표시 시점에 lazy 생성된다.
    /// 첫 생성 시 저장된 분할 트리를 넘겨 복원한다(있으면).
    func store(for workspace: Workspace) -> TerminalStore {
        if let s = stores[workspace.id] { return s }
        let s = TerminalStore(app: app, cwd: workspace.path, restoreTree: savedLayouts[workspace.id])
        stores[workspace.id] = s
        return s
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

    // MARK: 영속 (메타데이터 + 워크스페이스별 분할 트리)

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
        // 구버전(v3) 파일엔 없음 → 옵셔널(decodeIfPresent)로 하위호환. PTY는 복원 안 됨(새 셸).
        var layouts: [String: ExternalTreeNode]?
    }

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.v3.json")
    }()

    func save() {
        // 인스턴스화된 스토어의 현재 분할 트리를 반영한다. 아직 안 채워진(빈) 스토어는 스킵해
        // 저장된 좋은 레이아웃을 빈 트리로 덮어쓰지 않는다. 안 연 워크스페이스 것은 그대로 보존.
        for (id, store) in stores where !store.controller.allTabIds.isEmpty {
            savedLayouts[id] = store.controller.treeSnapshot()
        }
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode, layouts: savedLayouts)
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
