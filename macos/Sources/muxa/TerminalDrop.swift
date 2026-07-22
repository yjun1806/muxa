import Foundation

/// 터미널에 떨군 파일 경로를 프롬프트에 삽입할 텍스트로 바꾸는 순수 로직.
///
/// 드롭 이벤트 자체는 Bonsplit이 받는다 — 패인마다 `.onDrop(of: [.tabTransfer, .fileURL])`을 깔아두므로
/// 파일 드래그의 목적지는 그 중첩 호스팅 뷰가 되고, AppKit은 거기서 조상 뷰로 폴백하지 않는다.
/// 그래서 TermView에 NSDraggingDestination을 달아도 닿지 않는다(수신은 `TerminalStore.controller.onExternalFileDrop`).
enum TerminalDrop {
    /// 여러 경로를 한 줄의 터미널 입력으로 — 각 경로를 셸 이스케이프해 공백으로 잇는다.
    static func insertionText(for paths: [String]) -> String {
        paths.map(shellEscaped).joined(separator: " ")
    }

    /// 드롭 경로를 셸 입력으로 넘길 때의 이스케이프 — **따옴표로 감싸지 않고 문자마다 백슬래시**를 붙인다.
    /// 이렇게 하는 이유는 Claude Code의 파싱 때문이다: 경로가 **백슬래시 이스케이프된 토큰**일 때만
    /// 이미지 첨부로 인식하고, `'/path/img.png'`처럼 통째로 인용하면 경로로 안 봐 첨부가 실패한다.
    /// 이스케이프 대상은 셸이 단어 분리·글롭·확장에 쓰는 메타문자 집합(터미널이 드래그로 넣는 경로에서
    /// 이스케이프하는 문자와 같다). 예외로, 개행/캐리지리턴이 든 값은 백슬래시로 막으면 입력이 쪼개지므로
    /// 통째로 단일 인용한다.
    static func shellEscaped(_ value: String) -> String {
        if value.contains("\n") || value.contains("\r") {
            return "'\(value.replacingOccurrences(of: "'", with: #"'\''"#))'"
        }
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if shellMetacharacters.contains(scalar) { out.unicodeScalars.append("\\") }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// 백슬래시를 앞에 붙일 셸 메타문자. 멤버십으로 판정하므로 백슬래시 자신도 안전하게 한 번만 이스케이프된다.
    private static let shellMetacharacters = CharacterSet(charactersIn: #" ()[]{}<>"'`!#$&;|*?\"# + "\t")
}
