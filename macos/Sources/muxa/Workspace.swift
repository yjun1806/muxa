import Foundation

/// 워크스페이스 = 경로 + 표시 이름. 분할·탭 상태는 Bonsplit(TerminalStore)이 소유하므로
/// 여기엔 메타데이터만 둔다. (src/workspace.ts 이식, Bonsplit 이관으로 tree/tabs 제거)
struct Workspace: Codable, Identifiable {
    let id: String
    var path: String? // 셸 cwd. 초기 워크스페이스는 프로세스 cwd라 nil일 수 있다
    var name: String // 표시 이름(경로 basename)
}

func newId() -> String {
    UUID().uuidString
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

func createWorkspace(path: String? = nil, name: String? = nil) -> Workspace {
    Workspace(id: newId(), path: path, name: name ?? (path.map(basename) ?? "workspace"))
}
