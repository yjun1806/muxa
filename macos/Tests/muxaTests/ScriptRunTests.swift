import Bonsplit
import Foundation
import Testing
@testable import muxa

/// SCRIPT-TAB 2단계 — ScriptRun 전이 규칙(순수).
///
/// 프레임(script-exit)과 탭 닫힘(close_surface_cb)은 메인 큐에서 **어느 순서로 올지 모른다**.
/// 전이 규칙이 두 순서를 같은 결과로 수렴시켜야 칩이 running에 갇히거나(프레임 유실)
/// 잘못된 ✓를 지어내지(닫힘=성공 단정) 않는다.
struct ScriptRunTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)

    private func makeRun(state: ScriptRun.RunState = .running) -> ScriptRun {
        ScriptRun(scriptId: "s1", tabId: TabID(uuid: UUID()), name: "build",
                  startedAt: Self.t0, state: state)
    }

    // MARK: 정상 경로 — 프레임이 닫힘보다 먼저

    @Test("프레임 도착: running → finished(code), duration은 시작 시각부터 잰다")
    func 프레임전이() {
        let next = makeRun().receivingExit(code: 0, at: Self.t0.addingTimeInterval(8))
        #expect(next.state == .finished(code: 0, duration: 8))
    }

    @Test("실패 code(≠0)도 그대로 기록된다 — 칩이 exit N을 보여줄 원천")
    func 실패코드기록() {
        let next = makeRun().receivingExit(code: 2, at: Self.t0.addingTimeInterval(3))
        #expect(next.state == .finished(code: 2, duration: 3))
    }

    @Test("프레임이 먼저 온 뒤 탭 닫힘: closingFallback은 확정 결과를 안 덮는다")
    func 프레임후닫힘() {
        let finished = makeRun().receivingExit(code: 0, at: Self.t0.addingTimeInterval(8))
        let next = finished.closingFallback(at: Self.t0.addingTimeInterval(9))
        #expect(next == finished)
    }

    // MARK: 역순 경로 — 탭이 먼저 닫히고 프레임이 늦게 도착

    @Test("탭 닫힘 폴백: running → finished(code nil) — 성공으로 단정하지 않는다")
    func 폴백마감() {
        let next = makeRun().closingFallback(at: Self.t0.addingTimeInterval(5))
        #expect(next.state == .finished(code: nil, duration: 5))
    }

    @Test("폴백 선마감 뒤 늦은 프레임: code만 덮고 duration은 선마감 값을 유지한다")
    func 폴백후프레임() {
        let closed = makeRun().closingFallback(at: Self.t0.addingTimeInterval(5))
        let next = closed.receivingExit(code: 0, at: Self.t0.addingTimeInterval(30))
        // duration 30이 아니라 5 — 닫힘 시점이 실제 종료에 더 가깝다(프레임 도착은 큐 지연을 탄다).
        #expect(next.state == .finished(code: 0, duration: 5))
    }

    // MARK: 멱등 — 중복 이벤트가 첫 판정을 못 뒤집는다

    @Test("이미 code가 확정된 run에 중복 프레임: 무시된다")
    func 중복프레임무시() {
        let finished = makeRun().receivingExit(code: 0, at: Self.t0.addingTimeInterval(8))
        let next = finished.receivingExit(code: 1, at: Self.t0.addingTimeInterval(20))
        #expect(next == finished)
    }

    @Test("폴백 마감을 두 번 해도 duration이 늘어나지 않는다")
    func 중복폴백무시() {
        let closed = makeRun().closingFallback(at: Self.t0.addingTimeInterval(5))
        let next = closed.closingFallback(at: Self.t0.addingTimeInterval(60))
        #expect(next == closed)
    }
}
