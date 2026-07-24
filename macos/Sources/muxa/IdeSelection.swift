import Foundation

/// Claude Code IDE 통합에서 CLI에 넘기는 "현재 선택"(값 타입·순수). 좌표는 0-기반 line/character
/// (VS Code·LSP 규약). WebView 등 경계에서 관측한 선택을 이 값으로 정규화하고, 서버(IdeServer)가
/// 프로토콜 JSON(selection_changed·getCurrentSelection)으로 직렬화한다. 부작용은 서버에만 있다.
struct IdeSelection: Equatable {
    var filePath: String
    var text: String
    var startLine: Int
    var startCharacter: Int
    var endLine: Int
    var endCharacter: Int

    /// 선택 없음(커서만) — 텍스트가 비었다.
    var isEmpty: Bool { text.isEmpty }

    /// `file://` URL — 프로토콜의 `fileUrl` 필드. 공백·유니코드 경로도 안전하게 인코딩한다.
    var fileURL: String { URL(fileURLWithPath: filePath).absoluteString }

    /// 선택 없는 상태(파일만 활성, 커서 위치 미상) — start==end, 빈 텍스트.
    static func empty(filePath: String) -> IdeSelection {
        IdeSelection(filePath: filePath, text: "", startLine: 0, startCharacter: 0, endLine: 0, endCharacter: 0)
    }
}
