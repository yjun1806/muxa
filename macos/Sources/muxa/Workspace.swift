import Foundation

/// 탭 하나 = 제목 + 자기 분할 트리 + 포커스. (DESIGN.md 4.1 — 워크스페이스별 터미널 탭)
/// 이름을 TermTab으로 둔 이유: SwiftUI(macOS 15+)에 Tab 타입이 있어 충돌하기 때문.
struct TermTab: Codable, Identifiable {
    let id: String
    var title: String
    var tree: TreeNode
    var focusedId: String
}

/// 워크스페이스 하나 = 경로 + 터미널 탭 N개. (src/workspace.ts 확장)
struct Workspace: Codable, Identifiable {
    let id: String
    var path: String? // 셸 cwd. 초기 워크스페이스는 프로세스 cwd라 nil일 수 있다
    var name: String // 표시 이름(경로 basename)
    var tabs: [TermTab]
    var activeTabId: String

    var activeTab: TermTab? { tabs.first { $0.id == activeTabId } }
}

func basename(_ path: String) -> String {
    let trimmed = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    let parts = trimmed.split(separator: "/")
    return parts.last.map(String.init) ?? path
}

/// 표시용 경로 — 홈 접두를 ~로 축약.
func displayPath(_ path: String?, home: String?) -> String {
    guard let path else { return "" }
    if let home, path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
    return path
}

func createTab(title: String = "터미널") -> TermTab {
    let pane = makePane()
    return TermTab(id: newId(), title: title, tree: pane, focusedId: pane.id)
}

func createWorkspace(path: String? = nil, name: String? = nil) -> Workspace {
    let tab = createTab()
    return Workspace(
        id: newId(),
        path: path,
        name: name ?? (path.map(basename) ?? "workspace"),
        tabs: [tab],
        activeTabId: tab.id
    )
}
