import Foundation

/// 터미널에 떨군 파일 경로를 프롬프트에 삽입할 텍스트로 바꾸는 순수 로직.
///
/// 드롭 이벤트 자체는 Bonsplit이 받는다 — 패인마다 `.onDrop(of: [.tabTransfer, .fileURL])`을 깔아두므로
/// 파일 드래그의 목적지는 그 중첩 호스팅 뷰가 되고, AppKit은 거기서 조상 뷰로 폴백하지 않는다.
/// 그래서 TermView에 NSDraggingDestination을 달아도 닿지 않는다(수신은 `TerminalStore.controller.onFileDrop`).
enum TerminalDrop {
    /// 여러 경로를 한 줄의 터미널 입력으로 — 각 경로를 셸 이스케이프해 공백으로 잇는다.
    static func insertionText(for paths: [String]) -> String {
        paths.map(shellEscaped).joined(separator: " ")
    }

    /// 셸에 안전하게 넘길 이스케이프 — **따옴표로 감싸지 않고 문자마다 백슬래시**를 붙인다(cmux 동일).
    /// claude code는 드롭된 경로를 "터미널이 드래그로 넣어준 경로" 형태(백슬래시 이스케이프)로만 이미지
    /// 첨부로 인식한다. `'/path/img.png'`처럼 통째로 인용하면 경로로 보지 않아 첨부가 안 된다.
    /// 개행이 든 값만 예외로 단일 인용한다(개행은 백슬래시로 이스케이프하면 입력이 쪼개진다).
    static func shellEscaped(_ value: String) -> String {
        guard !value.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var result = value
        for char in shellEscapeCharacters {
            result = result.replacingOccurrences(of: String(char), with: "\\\(char)")
        }
        return result
    }

    /// 백슬래시를 붙일 셸 특수문자 — 백슬래시 자신이 맨 앞이어야 뒤 문자의 이스케이프가 이중으로 먹지 않는다.
    private static let shellEscapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"
}
