import XCTest
@testable import muxa

/// 훅 와이어 프레임 파싱 — `hook\t<tabId>\t<event>\n<원본 JSON>`.
/// payload에 개행·탭이 들어와도 안 깨지는 게 핵심(줄 단위 프로토콜과 공존한다).
final class HookFrameParseTests: XCTestCase {
    func testParsesHeaderAndPayload() {
        let frame = "hook\tTAB-1\tStop\n{\"last_assistant_message\":\"끝\"}"
        let msg = NotifyServer.parseHook(frame)
        XCTAssertEqual(msg?.tabId, "TAB-1")
        XCTAssertEqual(msg?.event, .stop)
        XCTAssertEqual(msg?.payload.lastAssistantMessage, "끝")
    }

    /// JSON 본문에 개행이 들어와도 첫 개행만 경계로 쓴다(pretty-printed payload가 와도 안전).
    func testPayloadWithNewlinesSurvives() {
        let frame = "hook\tTAB-1\tStop\n{\n  \"is_interrupt\": true\n}"
        XCTAssertEqual(NotifyServer.parseHook(frame)?.payload.isInterrupt, true)
    }

    /// payload의 탭(JSON에선 `\t`로 이스케이프돼 온다)이 헤더 필드로 오인되지 않고 값으로 살아남는다.
    /// 헤더는 첫 줄만 탭으로 쪼개므로 본문은 손대지 않는다 — 줄 단위 프로토콜이라면 여기서 깨진다.
    func testPayloadWithTabsSurvives() {
        let frame = #"hook\#tTAB-1\#tPostToolUse\#n{"tool_name":"Bash","tool_input":{"command":"a\tb"}}"#
        let msg = NotifyServer.parseHook(frame)
        XCTAssertEqual(msg?.payload.toolName, "Bash")
        XCTAssertEqual(msg?.payload.toolInput["command"], "a\tb", "이스케이프된 탭이 값으로 복원돼야 한다")
    }

    /// payload가 비었거나 깨져도 이벤트만으로 상태 전이는 유효하다 — 프레임을 버리지 않는다.
    func testEmptyOrBrokenPayloadStillYieldsEvent() {
        XCTAssertEqual(NotifyServer.parseHook("hook\tTAB-1\tStop\n")?.event, .stop)
        XCTAssertEqual(NotifyServer.parseHook("hook\tTAB-1\tStop")?.event, .stop)
        XCTAssertEqual(NotifyServer.parseHook("hook\tTAB-1\tStop\nnot json")?.event, .stop)
    }

    /// 모르는 이벤트는 버린다(스키마가 늘어도 안 깨진다).
    func testUnknownEventIsRejected() {
        XCTAssertNil(NotifyServer.parseHook("hook\tTAB-1\tSomeFutureEvent\n{}"))
    }

    func testMalformedHeaderIsRejected() {
        XCTAssertNil(NotifyServer.parseHook("hook\tTAB-1\n{}"), "이벤트 필드가 없다")
        XCTAssertNil(NotifyServer.parseHook("hook\t\tStop\n{}"), "tabId가 비었다")
    }

    /// 기존 줄 단위 프로토콜(muxa notify --state)은 hook 프레임으로 오인되면 안 된다.
    func testLegacyLineIsNotAHookFrame() {
        XCTAssertNil(NotifyServer.parseHook("TAB-1\tdone\t제목\t본문"))
        XCTAssertNotNil(NotifyServer.parse("TAB-1\tdone\t제목\t본문"), "레거시 경로는 그대로 살아야 한다")
    }
}
