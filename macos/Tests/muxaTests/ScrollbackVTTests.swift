import Testing
@testable import muxa

/// VT 스크롤백 위생(순수) — 색은 살리고, 테마를 굽는 시퀀스는 걷어낸다.
///
/// 평문 경로(`strip`)와 달리 SGR·OSC 8을 **보존**해야 복원 화면에 색이 남는다.
/// 대신 캡처 당시 테마가 구워진 OSC 색상 정의를 그대로 재주입하면, 테마를 바꾼 뒤 복원할 때
/// 흰 배경에 흰 글자가 된다(cmux 이슈 #5165와 같은 함정).
struct ScrollbackVTTests {
    private let esc = "\u{1B}"

    @Test func SGR_색상은_보존된다() {
        let out = ScrollbackText.sanitizeVT("\(esc)[31mred\(esc)[0m")
        #expect(out.contains("\(esc)[31m"))
        #expect(out.contains("red"))
    }

    @Test func OSC_팔레트_정의는_제거된다() {
        // OSC 4(팔레트) / 10(fg) / 11(bg) — 캡처 당시 테마가 구워진 시퀀스.
        let raw = "\(esc)]4;1;rgb:ff/00/00\u{07}\(esc)]10;#ffffff\u{07}\(esc)]11;#000000\u{07}hello"
        let out = ScrollbackText.sanitizeVT(raw)
        #expect(out.contains("hello"))
        #expect(!out.contains("]4;"))
        #expect(!out.contains("]10;"))
        #expect(!out.contains("]11;"))
    }

    @Test func OSC_8_하이퍼링크는_보존된다() {
        let raw = "\(esc)]8;;https://example.com\u{07}link\(esc)]8;;\u{07}"
        let out = ScrollbackText.sanitizeVT(raw)
        #expect(out.contains("]8;;https://example.com"))
        #expect(out.contains("link"))
    }

    @Test func 앞뒤를_reset으로_감싼다() {
        // 잔여 속성이 새 프롬프트로 새지 않도록.
        let out = ScrollbackText.sanitizeVT("plain")
        #expect(out.hasPrefix("\(esc)[0m"))
        #expect(out.hasSuffix("\(esc)[0m"))
    }

    @Test func 빈_입력은_빈_문자열() {
        #expect(ScrollbackText.sanitizeVT("") == "")
        #expect(ScrollbackText.sanitizeVT("   ") == "")
    }

    @Test func 바이트_상한_초과시_깨진_첫줄을_버린다() {
        // 꼬리를 남기며 자르면 첫 줄 중간이 잘려 "31m" 같은 이스케이프 잔해가 본문으로 출력된다.
        // 잘린 첫 줄은 통째로 버려야 화면이 오염되지 않는다.
        let long = "\(esc)[31m" + String(repeating: "A", count: 300) + "\n" + "\(esc)[32mtail\(esc)[0m"
        let out = ScrollbackText.sanitizeVT(long, maxBytes: 60)
        #expect(out.contains("tail"))
        #expect(!out.contains("31m")) // 깨진 SGR 잔해가 텍스트로 남으면 안 된다
        #expect(!out.contains("AAA")) // 잘린 첫 줄은 통째로 버린다
    }

    @Test func 줄_상한은_꼬리를_남긴다() {
        let raw = (1...10).map { "line\($0)" }.joined(separator: "\n")
        let out = ScrollbackText.sanitizeVT(raw, maxLines: 3)
        #expect(out.contains("line10"))
        #expect(!out.contains("line1\n")) // 앞쪽은 버려진다
    }
}
