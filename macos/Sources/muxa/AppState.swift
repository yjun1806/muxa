import Foundation
import Observation

/// 앱 전역 상태 + 영속(JSON 파일). (src/store.ts 이식, @Observable로 SwiftUI 자동 관찰)
///
/// 재시작 시 워크스페이스·탭·레이아웃·cwd·사이드바 모드가 복원된다.
/// PTY는 프로세스라 복원 불가 → 트리 구조/cwd만 저장하고 서피스는 새로 만든다.
///
/// 트리 변경(분할/드래그)은 빈번하므로 updateTab은 SwiftUI 갱신을 트리거하지 않도록
/// @ObservationIgnored 경로로 저장만 한다 — WorkspaceView가 자체 렌더하기 때문.
@Observable
final class AppState {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeId: String = ""
    private(set) var sidebarMode: SidebarMode = .expanded

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
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

    // MARK: 탭 액션

    func addTab(wsId: String) {
        guard let w = index(of: wsId) else { return }
        let tab = createTab()
        workspaces[w].tabs.append(tab)
        workspaces[w].activeTabId = tab.id
        save()
    }

    func closeTab(wsId: String, tabId: String) {
        guard let w = index(of: wsId), workspaces[w].tabs.count > 1 else { return }
        workspaces[w].tabs.removeAll { $0.id == tabId }
        if workspaces[w].activeTabId == tabId {
            workspaces[w].activeTabId = workspaces[w].tabs.first?.id ?? ""
        }
        save()
    }

    func setActiveTab(wsId: String, tabId: String) {
        guard let w = index(of: wsId) else { return }
        workspaces[w].activeTabId = tabId
        save()
    }

    /// 탭의 트리 변경(분할/닫기/드래그/포커스) 반영 — 저장만, SwiftUI 갱신 없음.
    func updateTab(wsId: String, tabId: String, tree: TreeNode, focusedId: String) {
        guard let w = index(of: wsId),
              let t = workspaces[w].tabs.firstIndex(where: { $0.id == tabId })
        else { return }
        // 관찰 트리거를 피하려고 내부 배열을 직접 바꾸지 않고, 저장용 스냅샷만 갱신한다.
        workspaces[w].tabs[t].tree = tree
        workspaces[w].tabs[t].focusedId = focusedId
        save()
    }

    private func index(of wsId: String) -> Int? {
        workspaces.firstIndex { $0.id == wsId }
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
        return dir.appendingPathComponent("state.v2.json")
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
