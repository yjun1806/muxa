import Testing
@testable import muxa

/// AgentActivityEstimator 순수 상태 전이 검증 — 명시 신호 pin + idle 추정. (ARCHITECTURE 4.5)
struct AgentActivityEstimatorTests {
    @Test func initialIdle() {
        #expect(AgentActivityEstimator().state == .idle)
    }

    @Test func heartbeatGoesWorking() {
        let e = AgentActivityEstimator().applying(.outputHeartbeat, now: 100)
        #expect(e.state == .working)
        #expect(e.needsIdleTick)
    }

    @Test func tickAfterIdleThresholdGoesWaiting() {
        let working = AgentActivityEstimator(idleThreshold: 4).applying(.outputHeartbeat, now: 100)
        let stillWorking = working.applying(.tick, now: 103)  // 3s < 4s
        #expect(stillWorking.state == .working)
        let waiting = working.applying(.tick, now: 105)       // 5s ≥ 4s
        #expect(waiting.state == .waiting)
    }

    @Test func explicitWaitingPinsAndIgnoresHeartbeat() {
        let waiting = AgentActivityEstimator().applying(.explicit(.waiting), now: 100)
        #expect(waiting.state == .waiting)
        // pin 중엔 노이즈 heartbeat가 상태를 되돌리지 못한다
        let afterNoise = waiting.applying(.outputHeartbeat, now: 101)
        #expect(afterNoise.state == .waiting)
        #expect(!waiting.needsIdleTick)
    }

    @Test func explicitWorkingPinsAndIgnoresTick() {
        let waiting = AgentActivityEstimator().applying(.explicit(.waiting), now: 100)
        let resumed = waiting.applying(.explicit(.working), now: 102)
        #expect(resumed.state == .working)
        // 훅이 working이라 확언했으면 조용한 도구 실행 중 tick이 "입력 대기"로 뒤집지 못한다(고정).
        #expect(resumed.applying(.tick, now: 110).state == .working)
        #expect(!resumed.needsIdleTick)
    }

    /// working이 고정돼도 다음 명시 훅은 상태를 바꾼다 — A안이 의존하는 핵심 불변식.
    /// (누가 .explicit에 `guard !pinned`를 붙이면 상태가 working에 영구 고착되므로 여기서 못 박는다.)
    @Test func hooksOverrideWorkingPin() {
        let working = AgentActivityEstimator().applying(.explicit(.working), now: 100)
        #expect(working.applying(.explicit(.waiting), now: 101).state == .waiting)
        #expect(working.applying(.explicit(.done), now: 101).state == .done)
    }

    /// 명시 유휴(idle_prompt)는 idle로 **고정**한다 — 끝나고 앉아 있는 걸 "대기"로 오판하지 않게,
    /// 커서 깜빡임 heartbeat로 working으로 되돌지도 않게. 다음 명시 신호(userPromptSubmit→working)만 바꾼다.
    @Test func explicitIdlePinsAndIgnoresHeartbeat() {
        let idle = AgentActivityEstimator().applying(.explicit(.working), now: 100).applying(.explicit(.idle), now: 105)
        #expect(idle.state == .idle)
        #expect(idle.applying(.outputHeartbeat, now: 106).state == .idle) // 노이즈 heartbeat 무시
        #expect(!idle.needsIdleTick)
        #expect(idle.applying(.explicit(.working), now: 107).state == .working) // 새 턴은 되살린다
    }

    @Test func commandFinishedGoesDoneAndUnpins() {
        let done = AgentActivityEstimator().applying(.explicit(.waiting), now: 100).applying(.commandFinished, now: 101)
        #expect(done.state == .done)
        // 완료는 pin 해제 → 새 출력이 오면 다시 working
        #expect(done.applying(.outputHeartbeat, now: 102).state == .working)
    }

    @Test func processExitedPinsDone() {
        let exited = AgentActivityEstimator().applying(.outputHeartbeat, now: 100).applying(.processExited, now: 101)
        #expect(exited.state == .done)
        // 종료 후 노이즈 heartbeat는 무시(pin)
        #expect(exited.applying(.outputHeartbeat, now: 102).state == .done)
    }

    @Test func borderColorForAllButIdle() {
        // 진행중도 이제 상시 표시(칸 테두리 계속 켜짐) — idle만 표시 없음.
        #expect(AgentActivity.working.borderColor != nil)
        #expect(AgentActivity.waiting.borderColor != nil)
        #expect(AgentActivity.done.borderColor != nil)
        #expect(AgentActivity.idle.borderColor == nil)
    }
}
