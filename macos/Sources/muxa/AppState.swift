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

    init(app: ghostty_app_t) {
        self.app = app
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }

    /// 워크스페이스의 터미널 스토어(없으면 생성). 표시 시점에 lazy 생성된다.
    func store(for workspace: Workspace) -> TerminalStore {
        if let s = stores[workspace.id] { return s }
        let s = TerminalStore(app: app, cwd: workspace.path)
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

    // MARK: 영속 (메타데이터만 — Bonsplit 레이아웃 복원은 후속)

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
    }

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.v3.json")
    }()

    func save() {
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode)
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
