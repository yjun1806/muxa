import XCTest
@testable import muxa

/// AgentActivityEstimator 순수 상태 전이 검증 — 명시 신호 pin + idle 추정. (ARCHITECTURE 4.5)
final class AgentActivityEstimatorTests: XCTestCase {
    func testInitialIdle() {
        XCTAssertEqual(AgentActivityEstimator().state, .idle)
    }

    func testHeartbeatGoesWorking() {
        let e = AgentActivityEstimator().applying(.outputHeartbeat, now: 100)
        XCTAssertEqual(e.state, .working)
        XCTAssertTrue(e.needsIdleTick)
    }

    func testTickAfterIdleThresholdGoesWaiting() {
        let working = AgentActivityEstimator(idleThreshold: 4).applying(.outputHeartbeat, now: 100)
        let stillWorking = working.applying(.tick, now: 103)  // 3s < 4s
        XCTAssertEqual(stillWorking.state, .working)
        let waiting = working.applying(.tick, now: 105)       // 5s ≥ 4s
        XCTAssertEqual(waiting.state, .waiting)
    }

    func testExplicitWaitingPinsAndIgnoresHeartbeat() {
        let waiting = AgentActivityEstimator().applying(.explicit(.waiting), now: 100)
        XCTAssertEqual(waiting.state, .waiting)
        // pin 중엔 노이즈 heartbeat가 상태를 되돌리지 못한다
        let afterNoise = waiting.applying(.outputHeartbeat, now: 101)
        XCTAssertEqual(afterNoise.state, .waiting)
        XCTAssertFalse(waiting.needsIdleTick)
    }

    func testExplicitWorkingUnpins() {
        let waiting = AgentActivityEstimator().applying(.explicit(.waiting), now: 100)
        let resumed = waiting.applying(.explicit(.working), now: 102)
        XCTAssertEqual(resumed.state, .working)
        // 재개 후엔 idle 추정이 다시 작동
        XCTAssertEqual(resumed.applying(.tick, now: 110).state, .waiting)
    }

    func testCommandFinishedGoesDoneAndUnpins() {
        let done = AgentActivityEstimator().applying(.explicit(.waiting), now: 100).applying(.commandFinished, now: 101)
        XCTAssertEqual(done.state, .done)
        // 완료는 pin 해제 → 새 출력이 오면 다시 working
        XCTAssertEqual(done.applying(.outputHeartbeat, now: 102).state, .working)
    }

    func testProcessExitedPinsDone() {
        let exited = AgentActivityEstimator().applying(.outputHeartbeat, now: 100).applying(.processExited, now: 101)
        XCTAssertEqual(exited.state, .done)
        // 종료 후 노이즈 heartbeat는 무시(pin)
        XCTAssertEqual(exited.applying(.outputHeartbeat, now: 102).state, .done)
    }

    func testBorderColorOnlyForWaitingAndDone() {
        XCTAssertNotNil(AgentActivity.waiting.borderColor)
        XCTAssertNotNil(AgentActivity.done.borderColor)
        XCTAssertNil(AgentActivity.working.borderColor)
        XCTAssertNil(AgentActivity.idle.borderColor)
    }
}
