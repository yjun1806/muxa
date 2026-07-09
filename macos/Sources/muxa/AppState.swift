import Foundation

/// 앱 전역 상태 + 영속(JSON 파일). (src/store.ts 이식)
///
/// 재시작 시 워크스페이스 레이아웃·cwd·사이드바 모드가 복원된다.
/// PTY는 프로세스라 복원 불가 → 트리 구조/cwd만 저장하고 서피스는 새로 만든다.
///
/// 워크스페이스 목록·활성·모드가 바뀌면 onChange로 크롬(상단바·사이드바)을 갱신한다.
/// 트리 변경(분할/드래그)은 빈번하므로 onChange 없이 저장만 한다 — WorkspaceView가 자체 렌더.
final class AppState {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeId: String = ""
    private(set) var sidebarMode: SidebarMode = .expanded

    /// 워크스페이스 목록/활성/모드 변경 시 호출(UI 재구성).
    var onChange: (() -> Void)?

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }

    // MARK: 액션

    func setActiveId(_ id: String) {
        guard activeId != id else { return }
        activeId = id
        changed()
    }

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        changed()
    }

    @discardableResult
    func addWorkspace(path: String?) -> Workspace {
        let ws = createWorkspace(path: path)
        workspaces.append(ws)
        activeId = ws.id
        changed()
        return ws
    }

    /// 복원된 워크스페이스가 없을 때만 초기 워크스페이스를 만든다.
    func ensureInitial(path: String?) {
        guard workspaces.isEmpty else { return }
        let ws = createWorkspace(path: path)
        workspaces = [ws]
        activeId = ws.id
        changed()
    }

    /// 트리 변경(분할/닫기/드래그/포커스) 반영 — 저장만, 크롬 갱신 없음.
    func updateWorkspace(id: String, tree: TreeNode, focusedId: String) {
        guard let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].tree = tree
        workspaces[i].focusedId = focusedId
        save()
    }

    private func changed() {
        save()
        onChange?()
    }

    // MARK: 영속

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
    }

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.v1.json")
    }()

    func save() {
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// 저장된 상태를 복원한다(없으면 빈 상태).
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
