import Foundation
import Testing
@testable import muxa

/// 푸터 스크립트 칩의 순수 판정.
///
/// 칩 뷰(ScriptStrip)는 `ScriptChipMode.judge`가 고른 모드를 그리기만 한다 — 어느 모드인지,
/// 잔류를 언제 내리는지, ✓/✗/?를 언제 그리는지는 전부 여기서 못 박는다.
struct ScriptChipTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)

    private func run(_ scriptId: String, startedAt: TimeInterval? = 0,
                     state: ScriptRun.RunState = .running,
                     acknowledged: Bool = false) -> ScriptRun {
        ScriptRun(scriptId: scriptId, projectId: "p1", name: scriptId,
                  startedAt: startedAt.map { Self.t0.addingTimeInterval($0) },
                  state: state, acknowledged: acknowledged)
    }

    // MARK: 모드 판정

    @Test("등록 0개면 플레이스홀더(.empty) — 칩은 상시다(발견 지점을 숨기지 않는다)")
    func 등록없으면빈칩() {
        #expect(ScriptChipMode.judge(scriptCount: 0, runs: []) == .empty)
        let stale = [run("a", state: .finished(code: 2, duration: 1))]
        #expect(ScriptChipMode.judge(scriptCount: 0, runs: stale) == .empty)
    }

    @Test("등록만 있고 실행 이력이 없으면 평시(개수)")
    func 평시() {
        #expect(ScriptChipMode.judge(scriptCount: 3, runs: []) == .idle(count: 3))
    }

    @Test("실행 중이 잔류보다 우선하고, 여러 개면 최신 시작이 앞(시작 시각 미상은 뒤)")
    func 실행중우선_최신순() {
        let old = run("old", startedAt: 0)
        let new = run("new", startedAt: 10)
        let adopted = run("adopted", startedAt: nil) // 재시작 후 채택 — 시각 미상은 맨 뒤
        let done = run("done", startedAt: 5, state: .finished(code: 0, duration: 1))
        let mode = ScriptChipMode.judge(scriptCount: 4, runs: [old, done, adopted, new])
        #expect(mode == .running([new, old, adopted]))
    }

    @Test("완료 잔류: 실패가 성공보다 우선한다 — 성공이 더 최신이어도")
    func 잔류_실패최우선() {
        let fail = run("fail", startedAt: 0, state: .finished(code: 2, duration: 1))
        let ok = run("ok", startedAt: 10, state: .finished(code: 0, duration: 1))
        #expect(ScriptChipMode.judge(scriptCount: 2, runs: [ok, fail]) == .lingering(fail))
    }

    @Test("완료 잔류: 같은 급이면 최신이 이긴다")
    func 잔류_같은급이면최신() {
        let old = run("old", startedAt: 0, state: .finished(code: 0, duration: 1))
        let new = run("new", startedAt: 10, state: .finished(code: 0, duration: 1))
        #expect(ScriptChipMode.judge(scriptCount: 2, runs: [old, new]) == .lingering(new))
    }

    @Test("code nil(결과 미상)은 실패로 세지 않는다 — 실패 확정이 미상을 이긴다")
    func 미상은실패아님() {
        let unknown = run("unknown", startedAt: 10, state: .finished(code: nil, duration: 1))
        let fail = run("fail", startedAt: 0, state: .finished(code: 2, duration: 1))
        #expect(ScriptChipMode.judge(scriptCount: 2, runs: [unknown, fail]) == .lingering(fail))
        // 미상만 있으면 미상이 잔류한다(숨기지 않는다 — 무슨 일이 있었는지는 말한다).
        #expect(ScriptChipMode.judge(scriptCount: 1, runs: [unknown]) == .lingering(unknown))
    }

    @Test("확인된(acknowledged) 잔류는 다시 띄우지 않는다 — 클릭·새 실행으로 내려간 칩")
    func 확인된잔류는숨김() {
        let acked = run("a", state: .finished(code: 2, duration: 1), acknowledged: true)
        #expect(ScriptChipMode.judge(scriptCount: 1, runs: [acked]) == .idle(count: 1))
        // 확인 안 된 성공이 함께 있으면 그쪽이 잔류한다(확인된 실패가 성공을 가리지 않는다).
        let ok = run("b", startedAt: 5, state: .finished(code: 0, duration: 1))
        #expect(ScriptChipMode.judge(scriptCount: 2, runs: [acked, ok]) == .lingering(ok))
    }

    // MARK: 표시 규칙(ScriptStatusStyle) — 색맹 안전(글리프가 상태를 말한다)·✓ 안 지어내기

    @Test("글리프: 성공 ✓ / 실패 ✗ / 미상은 물음표(✓ 금지) / 실행중 ⟳ / 실행 전 점선 사각")
    func 글리프() {
        #expect(ScriptStatusStyle.glyph(.finished(code: 0, duration: 1)) == "checkmark.square")
        #expect(ScriptStatusStyle.glyph(.finished(code: 2, duration: 1)) == "xmark.square")
        #expect(ScriptStatusStyle.glyph(.finished(code: nil, duration: 1)) == "questionmark.square")
        #expect(ScriptStatusStyle.glyph(.running) == "arrow.triangle.2.circlepath")
        #expect(ScriptStatusStyle.glyph(nil) == "square.dashed")
    }

    @Test("VoiceOver 라벨: 실패는 exit code까지 말한다, 미상은 성공이라 말하지 않는다")
    func 라벨() {
        #expect(ScriptStatusStyle.label(.finished(code: 2, duration: 1)) == "실패 (exit 2)")
        #expect(ScriptStatusStyle.label(.finished(code: 0, duration: 1)) == "성공")
        #expect(ScriptStatusStyle.label(.finished(code: nil, duration: 1)) == "결과 미상")
        #expect(ScriptStatusStyle.label(.running) == "실행 중")
        #expect(ScriptStatusStyle.label(nil) == "실행 전")
    }

    @Test("꼬리표: 실행중=경과, 성공·미상=걸린 시간, 실패=exit N, 실행 전=없음")
    func 꼬리표() {
        let running = run("a", startedAt: 0)
        #expect(ScriptStatusStyle.tail(running, now: Self.t0.addingTimeInterval(12)) == "12s")
        let ok = run("b", state: .finished(code: 0, duration: 8))
        #expect(ScriptStatusStyle.tail(ok, now: Self.t0) == "8s")
        let fail = run("c", state: .finished(code: 2, duration: 8))
        #expect(ScriptStatusStyle.tail(fail, now: Self.t0) == "exit 2")
        let unknown = run("d", state: .finished(code: nil, duration: 8))
        #expect(ScriptStatusStyle.tail(unknown, now: Self.t0) == "8s")
        #expect(ScriptStatusStyle.tail(nil, now: Self.t0) == nil)
    }

    @Test("시각·시간 미상이면 꼬리표를 지어내지 않는다 — 채택된 실행(startedAt·duration nil)")
    func 꼬리표_미상없음() {
        let adopted = run("a", startedAt: nil)
        #expect(ScriptStatusStyle.tail(adopted, now: Self.t0) == nil)
        let adoptedDone = run("b", state: .finished(code: 0, duration: nil))
        #expect(ScriptStatusStyle.tail(adoptedDone, now: Self.t0) == nil)
    }
}
