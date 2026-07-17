import Foundation
import Testing
@testable import muxa

/// `ServiceMonitor`의 판정 — 죽음 전이 발화·취소 후 stale write·포트 백오프·재시작 시 포트 무효화.
///
/// 이 타입은 tmux 셸아웃을 주입받으므로(`states`/`capture`/`now`) tmux 없이 결정론적으로 검증된다.
/// 알림·배지의 유일한 결정론적 신호가 여기서 나오는데 종전엔 테스트가 0개였다.
@MainActor
struct ServiceMonitorTests {
    private let svc = Service(id: "S", name: "web", command: "pnpm dev")
    private let session = "muxa__P__S"

    /// 시각을 손으로 돌리는 시계 — 백오프는 벽시계에 매달리면 검증할 수 없다.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    /// 폴링 루프·앱 활성 관측 없이 `refresh`만 손으로 돌리는 모니터(테스트는 스케줄이 아니라 판정을 본다).
    private func monitor(states: @escaping () async -> [String: ServiceState],
                         capture: @escaping (String, String) async -> String = { _, _ in "" },
                         clock: Clock = Clock()) -> ServiceMonitor {
        ServiceMonitor(states: states, capture: capture, now: { clock.now }, observeAppActivity: false)
    }

    // MARK: 죽음 전이 — 정확히 1회

    @Test func 죽음은_정확히_한_번만_알린다() async {
        var pane: ServiceState = .running
        let m = monitor(states: { [session] in [session: pane] })
        var exits: [Int32] = []
        m.onExit = { _, code in exits.append(code) }

        await m.refresh(services: [svc]) // baseline: running
        pane = .exited(code: 1)
        await m.refresh(services: [svc]) // 죽었다 → 1회 발화
        await m.refresh(services: [svc]) // 계속 죽어 있다 → 다시 알리지 않는다
        await m.refresh(services: [svc])

        #expect(exits == [1])
        #expect(m.state(of: "S") == .exited(code: 1))
    }

    /// 첫 훑기는 baseline이다 — 앱을 켜기 전에 이미 죽어 있던 세션을 재알림하면 켤 때마다 시끄럽다.
    @Test func 기동_전에_죽어_있던_세션은_알리지_않는다() async {
        let m = monitor(states: { [self.session: ServiceState.exited(code: 2)] })
        var exits: [Int32] = []
        m.onExit = { _, code in exits.append(code) }

        await m.refresh(services: [svc])
        await m.refresh(services: [svc])

        #expect(exits.isEmpty)
        #expect(m.state(of: "S") == .exited(code: 2))
    }

    /// 첫 폴링 전에 즉사한 서비스(오타·포트 선점)는 running을 거치지 않는다 — 그래도 알려야 한다.
    @Test func baseline_뒤_즉사는_running을_안_거쳐도_알린다() async {
        var pane: [String: ServiceState] = [:]
        let m = monitor(states: { pane })
        var exits: [Int32] = []
        m.onExit = { _, code in exits.append(code) }

        await m.refresh(services: [svc]) // baseline: 아직 세션 없음(.missing)
        pane = [session: .exited(code: 127)] // command not found
        await m.refresh(services: [svc])

        #expect(exits == [127])
    }

    // MARK: R3 — 취소 후 stale write 금지

    /// 마지막 서비스를 지우면 sync가 states를 비우고 폴링을 멈춘다. 그때 `states()`를 await 중이던
    /// refresh가 재개해 아직 살아 있는 세션을 보고 삭제된 id를 되살리면, 폴링이 멈춰 그걸 지울 사람이
    /// 없다 — **삭제한 서비스의 칩이 영구히 남는다.** 세대 카운터가 그 대입을 버린다.
    @Test func 취소된_refresh는_삭제된_서비스를_되살리지_않는다() async {
        let box = MonitorBox()
        let m = monitor(states: { [session] in
            box.monitor?.sync(services: []) // 읽는 사이 마지막 서비스가 삭제됐다
            return [session: .running]
        })
        box.monitor = m

        await m.refresh(services: [svc])

        #expect(m.states.isEmpty)
        #expect(m.state(of: "S") == .missing)
    }

    /// 포트 조회(capture)도 await다 — 그 사이 sync가 오면 포트 역시 쓰지 않는다.
    @Test func 취소된_refresh는_포트도_쓰지_않는다() async {
        let box = MonitorBox()
        let m = monitor(states: { [self.session: ServiceState.running] },
                        capture: { _, _ in
                            box.monitor?.sync(services: [])
                            return "http://localhost:3000/"
                        })
        box.monitor = m

        await m.refresh(services: [svc])

        #expect(m.ports.isEmpty)
    }

    // MARK: C2 — 포트 조회는 포기하지 않고 간격을 늘린다

    @Test func 포트를_찾으면_캐시하고_다시_조회하지_않는다() async {
        var captures = 0
        let m = monitor(states: { [self.session: ServiceState.running] },
                        capture: { _, _ in
                            captures += 1
                            return "  ➜  Local:   http://localhost:3000/"
                        })
        await m.refresh(services: [svc])
        await m.refresh(services: [svc])

        #expect(m.ports["S"] == 3000)
        #expect(captures == 1)
    }

    /// 포트를 안 찍는 서비스(워커·`--watch`)를 2초마다 영원히 캡처하면 하루 4만 번 프로세스를 띄운다.
    /// 그렇다고 "5회 후 포기"면 콜드 컴파일로 늦게 뜨는 서버의 포트를 영영 못 잡는다 —
    /// 포기하지 않고 간격만 2배씩 늘린다(2 → 4 → … → 60초 상한).
    @Test func 포트를_못_찾으면_간격을_두_배씩_늘리고_60초에서_멈춘다() async {
        let clock = Clock()
        var probedAt: [TimeInterval] = []
        let m = monitor(states: { [self.session: ServiceState.running] },
                        capture: { _, _ in
                            probedAt.append(clock.now.timeIntervalSince1970)
                            return "compiling..." // 포트가 아직 없다
                        },
                        clock: clock)

        for _ in 0...200 { // 1초 틱으로 200초를 흘려보낸다(폴링보다 촘촘히 — 스케줄만 본다)
            await m.refresh(services: [svc])
            clock.advance(1)
        }

        #expect(probedAt == [0, 2, 6, 14, 30, 62, 122, 182])
        #expect(m.ports["S"] == nil) // 지어내지 않는다
    }

    /// 재시작하면 옛 포트를 버린다 — 3000이 아직 물려 있으면 새 프로세스는 3001을 잡는다.
    /// 캐시가 재시작을 살아남으면 칩이 거짓 포트를 띄우고, 그 순간 유일한 상시 신호가 신뢰를 잃는다.
    @Test func 재시작하면_포트_캐시를_버리고_다시_찾는다() async {
        var pane: ServiceState = .running
        var log = "http://localhost:3000/"
        let m = monitor(states: { [self.session: pane] }, capture: { _, _ in log })

        await m.refresh(services: [svc])
        #expect(m.ports["S"] == 3000)

        pane = .exited(code: 1) // 죽었다
        await m.refresh(services: [svc])
        pane = .running // 사용자가 재시작 → 새 프로세스, 새 포트
        log = "http://localhost:3001/"
        await m.refresh(services: [svc])

        #expect(m.ports["S"] == 3001)
    }

    // MARK: 신뢰 경계 밖의 세션 이름

    /// `__`가 든 id는 세션명 규약을 깨서 parse가 nil을 낸다. 그런 세션은 상태로 받아들이지 않는다
    /// (지어낸 상태를 칩에 띄우느니 .missing이 낫다). 남의 tmux 세션도 같은 이유로 걸러진다.
    @Test func 파싱_불가_세션은_상태로_받아들이지_않는다() async {
        let m = monitor(states: { ["muxa__P__we__b": .running, "my-work": .running, "muxa": .running] })
        await m.refresh(services: [Service(id: "we__b", name: "web", command: "pnpm dev")])

        #expect(m.states.isEmpty)
    }

    /// 등록되지 않은 서비스의 세션(다른 muxa 인스턴스·정리 전 좀비)은 상태에 섞이지 않는다.
    @Test func 등록되지_않은_서비스의_세션은_무시한다() async {
        let m = monitor(states: { ["muxa__P__OTHER": .running, self.session: .running] })
        await m.refresh(services: [svc])

        #expect(m.states == ["S": .running])
    }

    // MARK: 스크립트 관측 — 같은 폴링이 두 축을 다 배달한다

    /// 스크립트 세션은 scriptId 키로 골라 콜백에 싣고, 서비스 상태에는 섞이지 않는다.
    /// 추적 안 된 스크립트(타 인스턴스)·서비스 세션은 걸러진다.
    @Test func 스크립트_세션은_콜백으로만_배달한다() async {
        let m = monitor(states: { [self.session: ServiceState.running,
                                   "muxa__P__script__SC": .exited(code: 2),
                                   "muxa__P__script__OTHER": .running] })
        var polls: [[String: ServiceState]] = []
        m.onScriptsPoll = { polls.append($0) }

        await m.refresh(services: [svc], scriptIds: ["SC"])

        #expect(polls == [["SC": .exited(code: 2)]])
        #expect(m.states == ["S": .running]) // 서비스 축 오염 없음
    }

    /// 관측 0건이어도 발화한다 — "세션이 사라졌다"는 유예 지난 running을 마감하는 판정 입력이다.
    @Test func 스크립트_관측이_없어도_빈_관측을_발화한다() async {
        let m = monitor(states: { [:] })
        var polls: [[String: ServiceState]] = []
        m.onScriptsPoll = { polls.append($0) }

        await m.refresh(services: [], scriptIds: ["SC"])

        #expect(polls == [[:]])
    }
}

/// 주입한 클로저 안에서 모니터 자신을 다시 부르기 위한 상자(init 시점엔 아직 없어 캡처할 수 없다).
@MainActor
private final class MonitorBox {
    var monitor: ServiceMonitor?
}
