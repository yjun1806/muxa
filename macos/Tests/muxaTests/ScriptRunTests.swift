import Foundation
import Testing
@testable import muxa

/// ScriptRun 전이 규칙(순수) — tmux 폴링 관측 1회를 레지스트리에 합치는 `merging`.
///
/// 진실 원천은 tmux다: 실행 시작(runScript)은 낙관적으로 running을 심고, 이후는 관측이 끌고 간다.
/// 관측은 **어느 순서로 와도**(늦은 스냅샷·재시작 후 첫 폴링·세션 소멸) 결과를 지어내거나
/// 뒤집으면 안 된다 — ✓도 ✗도 관측 없이는 만들지 않는다.
struct ScriptRunTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)

    private func located(_ id: String = "s1", projectId: String = "p1",
                         name: String = "build") -> LocatedScript {
        LocatedScript(script: Script(id: id, name: name, command: "make \(name)"),
                      workspaceId: "w1", workspaceName: "메인",
                      projectId: projectId, projectName: "웹", cwd: "/repo")
    }

    private func running(_ id: String = "s1", startedAt: Date? = t0) -> ScriptRun {
        ScriptRun(scriptId: id, projectId: "p1", name: "build", startedAt: startedAt, state: .running)
    }

    // MARK: 정상 경로 — 시작 → running 관측 → exited 관측

    @Test("running 관측: 기존 running을 유지한다(startedAt 보존 — 경과 시계가 흔들리지 않는다)")
    func 실행유지() {
        let prev = ["s1": running()]
        let (next, exits) = ScriptRun.merging(runs: prev, observed: ["s1": .running],
                                              registered: [located()], now: Self.t0.addingTimeInterval(5))
        #expect(next["s1"] == prev["s1"])
        #expect(exits.isEmpty)
    }

    @Test("exited 관측: running → finished(code), duration은 시작 시각부터 잰다 + exits에 실린다")
    func 종료확정() {
        let (next, exits) = ScriptRun.merging(runs: ["s1": running()], observed: ["s1": .exited(code: 2)],
                                              registered: [located()], now: Self.t0.addingTimeInterval(8))
        #expect(next["s1"]?.state == .finished(code: 2, duration: 8))
        #expect(exits.map(\.scriptId) == ["s1"])
    }

    @Test("이미 finished인 run에 반복 exited 관측: 첫 판정 유지 + 재알림 없음")
    func 중복관측무시() {
        var done = running()
        done.state = .finished(code: 0, duration: 8)
        let (next, exits) = ScriptRun.merging(runs: ["s1": done], observed: ["s1": .exited(code: 0)],
                                              registered: [located()], now: Self.t0.addingTimeInterval(60))
        #expect(next["s1"] == done)
        #expect(exits.isEmpty)
    }

    // MARK: 관측 지연 — 막 시작한 실행이 스냅샷에 아직 없다

    @Test("missing인데 갓 시작(유예 안): running 유지 — in-flight 스냅샷 레이스에 마감하지 않는다")
    func 유예안유지() {
        let (next, exits) = ScriptRun.merging(runs: ["s1": running()], observed: [:],
                                              registered: [located()],
                                              now: Self.t0.addingTimeInterval(ScriptRun.missingGrace - 1))
        #expect(next["s1"]?.isRunning == true)
        #expect(exits.isEmpty)
    }

    @Test("missing이 유예를 넘김: 결과 미상(code nil)으로 마감 — 성공·실패 어느 쪽도 지어내지 않는다")
    func 유예후마감() {
        let now = Self.t0.addingTimeInterval(ScriptRun.missingGrace + 1)
        let (next, exits) = ScriptRun.merging(runs: ["s1": running()], observed: [:],
                                              registered: [located()], now: now)
        #expect(next["s1"]?.state == .finished(code: nil, duration: ScriptRun.missingGrace + 1))
        #expect(exits.isEmpty) // 결과 미상은 알리지 않는다
    }

    @Test("미상(code nil) 마감 뒤 늦은 exited 관측: code로 승격 + 잔류 부활 + exits에 실린다")
    func 미상승격() {
        var unknown = running()
        unknown.state = .finished(code: nil, duration: 11)
        unknown.acknowledged = true // 사용자가 "?"를 이미 확인했어도 — 새 판정은 다시 말한다
        let (next, exits) = ScriptRun.merging(runs: ["s1": unknown], observed: ["s1": .exited(code: 2)],
                                              registered: [located()], now: Self.t0.addingTimeInterval(60))
        // duration은 조기 마감 값 유지 — 이 관측은 폴 지연을 타서 60은 과대다.
        #expect(next["s1"]?.state == .finished(code: 2, duration: 11))
        #expect(next["s1"]?.acknowledged == false)
        #expect(exits.map(\.scriptId) == ["s1"]) // 미상엔 알림이 없었다 — 실패 확정은 여기서 처음 알린다
    }

    @Test("finished 뒤 세션이 사라져도(missing) 확정 결과는 남는다 — 칩 잔류·도크 진입점 유지")
    func 종료후소멸보존() {
        var done = running()
        done.state = .finished(code: 1, duration: 3)
        let (next, _) = ScriptRun.merging(runs: ["s1": done], observed: [:],
                                          registered: [located()], now: Self.t0.addingTimeInterval(99))
        #expect(next["s1"] == done)
    }

    // MARK: 채택 — muxa 재시작 후 첫 폴링이 기존 세션을 발견한다

    @Test("모르는 running 세션: 채택하되 startedAt은 nil — 경과를 지어내지 않는다")
    func 실행채택() {
        let (next, exits) = ScriptRun.merging(runs: [:], observed: ["s1": .running],
                                              registered: [located()], now: Self.t0)
        #expect(next["s1"]?.isRunning == true)
        #expect(next["s1"]?.startedAt == nil)
        #expect(next["s1"]?.acknowledged == false)
        #expect(exits.isEmpty)
    }

    @Test("모르는 exited 세션: 조용히 채택(acknowledged) — 재시작 전의 결과를 재알림·재잔류시키지 않는다")
    func 종료채택() {
        let (next, exits) = ScriptRun.merging(runs: [:], observed: ["s1": .exited(code: 0)],
                                              registered: [located()], now: Self.t0)
        #expect(next["s1"]?.state == .finished(code: 0, duration: nil))
        #expect(next["s1"]?.acknowledged == true)
        #expect(exits.isEmpty)
    }

    @Test("채택된 running(시작 시각 미상)이 사라지면: 유예 없이 결과 미상으로 마감")
    func 채택실행소멸() {
        let (next, _) = ScriptRun.merging(runs: ["s1": running(startedAt: nil)], observed: [:],
                                          registered: [located()], now: Self.t0)
        #expect(next["s1"]?.state == .finished(code: nil, duration: nil))
    }

    @Test("finished인데 running 관측: 새 실행으로 채택 — 다른 인스턴스가 재실행한 세션")
    func 재실행채택() {
        var done = running()
        done.state = .finished(code: 0, duration: 8)
        let (next, _) = ScriptRun.merging(runs: ["s1": done], observed: ["s1": .running],
                                          registered: [located()], now: Self.t0.addingTimeInterval(60))
        #expect(next["s1"]?.isRunning == true)
    }

    // MARK: 등록의 그림자 — 등록이 사라지면 run도 사라진다

    @Test("등록 해제된 스크립트의 run은 버린다 — 관측이 남아 있어도")
    func 등록해제정리() {
        let (next, exits) = ScriptRun.merging(runs: ["s1": running()], observed: ["s1": .running],
                                              registered: [], now: Self.t0)
        #expect(next.isEmpty)
        #expect(exits.isEmpty)
    }

    @Test("등록만 있고 관측도 run도 없으면: 엔트리를 만들지 않는다(실행 전)")
    func 실행전없음() {
        let (next, _) = ScriptRun.merging(runs: [:], observed: [:], registered: [located()], now: Self.t0)
        #expect(next.isEmpty)
    }

    // MARK: 잔류 확인 — acknowledge는 내리되 지우지 않는다

    @Test("acknowledgingFinished: 같은 프로젝트의 finished만 확인 처리, running·타 프로젝트는 그대로")
    func 잔류확인() {
        var done = running()
        done.state = .finished(code: 1, duration: 3)
        let other = ScriptRun(scriptId: "s2", projectId: "p2", name: "test",
                              startedAt: Self.t0, state: .finished(code: 1, duration: 2))
        let runs = ["s1": done, "s2": other, "s3": running("s3")]
        let next = ScriptRun.acknowledgingFinished(runs, projectId: "p1")
        #expect(next["s1"]?.acknowledged == true)
        #expect(next["s2"]?.acknowledged == false) // 다른 프로젝트 — 그 칩의 잔류는 그대로
        #expect(next["s3"]?.acknowledged == false) // running은 잔류가 아니다
        #expect(next["s1"]?.state == done.state) // 결과 자체는 그대로 — 로그 진입점이 산다
    }
}
