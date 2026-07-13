import XCTest
@testable import muxa

/// 훅 해석기 — 완료 오탐(가짜 done) 차단이 핵심이다. 배경 작업·서브에이전트가 남으면 완료가 아니다.
final class ClaudeHookInterpreterTests: XCTestCase {
    /// 훅 payload JSON을 만들어 파싱까지 태운다(파서와 해석기를 함께 검증).
    private func payload(_ json: String) -> ClaudeHookPayload {
        guard let parsed = ClaudeHookPayload.parse(Data(json.utf8)) else {
            XCTFail("payload 파싱 실패: \(json)")
            return ClaudeHookPayload.parse(Data("{}".utf8))!
        }
        return parsed
    }

    private func interpret(
        _ event: ClaudeHookEvent, _ json: String = "{}", state: HookSessionState = HookSessionState()
    ) -> (outcome: HookOutcome, state: HookSessionState) {
        ClaudeHookInterpreter.interpret(event: event, payload: payload(json), state: state)
    }

    // MARK: 완료 판정

    func testStopWithoutBackgroundWorkIsDone() {
        let r = interpret(.stop, #"{"last_assistant_message": "다 고쳤다"}"#)
        XCTAssertEqual(r.outcome.state, .done)
        XCTAssertEqual(r.outcome.category, .turnComplete)
        XCTAssertEqual(r.outcome.body, "다 고쳤다")
        XCTAssertTrue(r.outcome.clearsDetail)
        XCTAssertFalse(r.state.deferredDone)
    }

    /// 배경 작업이 도는 동안의 Stop은 완료가 아니다 — 알림도 없다.
    func testStopWithRunningBackgroundTaskIsNotDone() {
        let json = #"{"background_tasks": [{"status": "running"}]}"#
        let r = interpret(.stop, json)
        XCTAssertEqual(r.outcome.state, .working)
        XCTAssertNil(r.outcome.category, "배경 작업 중엔 완료 알림이 나가면 안 된다")
        XCTAssertTrue(r.state.deferredDone)
        XCTAssertTrue(r.state.pendingBackgroundWork)
    }

    func testStopWithFinishedBackgroundTaskIsDone() {
        let r = interpret(.stop, #"{"background_tasks": [{"status": "completed"}]}"#)
        XCTAssertEqual(r.outcome.state, .done)
        XCTAssertFalse(r.state.pendingBackgroundWork)
    }

    func testStopWithSessionCronIsNotDone() {
        let r = interpret(.stop, #"{"session_crons": [{"id": "x"}]}"#)
        XCTAssertNil(r.outcome.category)
        XCTAssertTrue(r.state.pendingBackgroundWork)
    }

    /// 리드가 Stop해도 서브에이전트가 살아있으면 완료가 아니고, 마지막 하나가 끝날 때 완료가 된다.
    func testDoneDeferredUntilLastSubagentStops() {
        var state = HookSessionState()
        state = interpret(.subagentStart, state: state).state
        state = interpret(.subagentStart, state: state).state
        XCTAssertEqual(state.liveSubagents, 2)

        let stopped = interpret(.stop, state: state)
        XCTAssertNil(stopped.outcome.category, "서브에이전트가 도는데 완료 알림이 나갔다")
        XCTAssertTrue(stopped.state.deferredDone)
        state = stopped.state

        let first = interpret(.subagentStop, state: state)
        XCTAssertNil(first.outcome.category, "아직 하나 남았다")
        state = first.state

        let last = interpret(.subagentStop, #"{"last_assistant_message": "끝"}"#, state: state)
        XCTAssertEqual(last.outcome.state, .done, "마지막 서브에이전트가 끝나면 그때가 완료다")
        XCTAssertEqual(last.outcome.category, .turnComplete)
        XCTAssertFalse(last.state.deferredDone)
    }

    /// 보류가 없었으면 서브에이전트 종료가 완료 알림을 만들지 않는다.
    func testSubagentStopWithoutDeferredDoneIsSilent() {
        var state = HookSessionState()
        state = interpret(.subagentStart, state: state).state
        let r = interpret(.subagentStop, state: state)
        XCTAssertNil(r.outcome.category)
        XCTAssertNil(r.outcome.state)
    }

    func testInterruptedStopIsLabeledDifferently() {
        let r = interpret(.stop, #"{"is_interrupt": true}"#)
        XCTAssertEqual(r.outcome.state, .done)
        XCTAssertEqual(r.outcome.title, "중단됨")
    }

    /// 본문이 없으면 transcript 경로를 실어 보내 경계가 꼬리에서 보강하게 한다.
    func testStopWithoutMessageRequestsTranscript() {
        let r = interpret(.stop, #"{"transcript_path": "/tmp/a.jsonl"}"#)
        XCTAssertEqual(r.outcome.transcriptPath, "/tmp/a.jsonl")
    }

    /// 본문이 이미 있으면 transcript를 읽을 필요가 없다(불필요한 파일 IO 금지).
    func testStopWithMessageSkipsTranscript() {
        let r = interpret(.stop, #"{"last_assistant_message": "됐다", "transcript_path": "/tmp/a.jsonl"}"#)
        XCTAssertNil(r.outcome.transcriptPath)
    }

    // MARK: 유휴 리마인더 게이팅 (Stop에서 캐시한 pending이 유일한 근거)

    /// idle_prompt payload에는 background_tasks가 없다 — Stop 때 캐시한 값으로 막아야 한다.
    func testIdleReminderSuppressedWhileBackgroundWorkPending() {
        let state = interpret(.stop, #"{"background_tasks": [{"status": "running"}]}"#).state
        let idle = interpret(.notification, #"{"notification_type": "idle_prompt"}"#, state: state)
        XCTAssertNil(idle.outcome.category, "배경 작업 중엔 유휴 리마인더가 나가면 안 된다")
        XCTAssertNil(idle.outcome.state)
    }

    func testIdleReminderDeliveredWhenNothingPending() {
        let r = interpret(.notification, #"{"notification_type": "idle_prompt"}"#)
        XCTAssertEqual(r.outcome.category, .idleReminder)
        XCTAssertEqual(r.outcome.state, .waiting)
    }

    /// 권한 요청은 배경 작업과 무관하게 항상 뜬다 — 사용자가 막고 있는 유일한 알림이다.
    func testPermissionNotificationAlwaysDelivered() {
        let state = interpret(.stop, #"{"background_tasks": [{"status": "running"}]}"#).state
        let r = interpret(.notification, #"{"message": "권한이 필요하다"}"#, state: state)
        XCTAssertEqual(r.outcome.category, .needsPermission)
        XCTAssertEqual(r.outcome.body, "권한이 필요하다")
    }

    // MARK: 승인 대기 · 진행 표시

    /// Claude는 AskUserQuestion 때 Notification 훅을 안 보낸다 — PreToolUse가 유일한 신호다.
    func testAskUserQuestionPreToolUseIsWaiting() {
        let r = interpret(.preToolUse, #"{"tool_name": "AskUserQuestion"}"#)
        XCTAssertEqual(r.outcome.state, .waiting)
        XCTAssertEqual(r.outcome.category, .needsPermission)
    }

    func testOtherToolsAreWorkingWithDetail() {
        let r = interpret(.postToolUse, #"{"tool_name": "Edit", "tool_input": {"file_path": "/a/b/TermView.swift"}}"#)
        XCTAssertEqual(r.outcome.state, .working)
        XCTAssertNil(r.outcome.category, "도구 진행은 알림이 아니다")
        XCTAssertEqual(r.outcome.detail, "편집 중: TermView.swift")
    }

    // MARK: 세션 경계

    func testUserPromptSubmitResetsStaleState() {
        let stale = HookSessionState(pendingBackgroundWork: true, liveSubagents: 3, deferredDone: true)
        let r = interpret(.userPromptSubmit, state: stale)
        XCTAssertEqual(r.state, HookSessionState(), "새 턴은 이전 턴 잔여를 전부 지운다")
        XCTAssertEqual(r.outcome.state, .working)
        XCTAssertTrue(r.outcome.clearsDetail)
    }

    func testSessionStartRegistersResumeBindingWithoutState() {
        let r = interpret(.sessionStart, #"{"session_id": "abc-123"}"#)
        XCTAssertNil(r.outcome.state, "세션이 떴을 뿐 작업 중은 아니다")
        XCTAssertEqual(r.outcome.resume?.command, "claude --resume abc-123")
        XCTAssertEqual(r.outcome.resume?.agentLabel, "claude")
    }

    // MARK: 스키마 방어

    /// 스키마가 바뀌어 필드가 통째로 사라져도 파싱은 성공하고 상태 전이는 살아야 한다.
    func testEmptyPayloadStillTransitions() {
        let r = interpret(.stop)
        XCTAssertEqual(r.outcome.state, .done, "필드가 없어도 Stop은 완료다")
        XCTAssertFalse(r.state.pendingBackgroundWork, "pending을 못 읽으면 false로 폴백한다(무음보다 오탐이 낫다)")
    }

    func testMalformedJSONIsRejected() {
        XCTAssertNil(ClaudeHookPayload.parse(Data("not json".utf8)))
        XCTAssertNil(ClaudeHookPayload.parse(Data("[1,2]".utf8)), "최상위가 객체가 아니면 버린다")
    }

    func testBodyIsClampedAndFlattened() {
        let long = String(repeating: "가", count: 300)
        let r = interpret(.stop, #"{"last_assistant_message": "줄1\n줄2"}"#)
        XCTAssertEqual(r.outcome.body, "줄1 줄2", "개행은 공백으로 뭉갠다")
        XCTAssertEqual(ClaudeHookInterpreter.clamp(long).count, ClaudeHookInterpreter.bodyMax + 1, "말줄임표 1자 포함")
    }
}
