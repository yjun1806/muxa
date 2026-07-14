import Foundation
import Testing
@testable import muxa

/// FSEvents 배치(0.3s)가 디바운스(0.5s)보다 촘촘히 계속 오는 동안 트레일링 재예약만 하면
/// flush가 **한 번도** 안 돈다 — `npm install`이 도는 내내 git 패널·익스플로러가 얼어붙는다.
/// 첫 신호 기준 상한(maxWait)이 그 무한 연기를 끊는다.
struct FileWatcherDebounceTests {
    typealias Schedule = FileWatcher.DebounceSchedule

    @Test func 조용해지면_트레일링_디바운스로_기다린다() {
        // 첫 신호 = 지금. 상한(1.5s)이 남아 있으니 평소대로 0.5초 뒤에 흘린다.
        #expect(Schedule.delay(now: 0, firstSignal: 0, debounce: 0.5, maxWait: 1.5) == 0.5)
    }

    @Test func 폭주가_이어져도_상한에서_끊긴다() {
        // 첫 신호로부터 1.2초가 지난 시점의 배치 — 트레일링대로면 1.7초(상한 초과)라 0.3초로 깎는다.
        let delay = Schedule.delay(now: 1.2, firstSignal: 0, debounce: 0.5, maxWait: 1.5)
        #expect(abs(delay - 0.3) < 0.0001)
    }

    @Test func 상한을_이미_넘겼으면_즉시_흘린다() {
        // 메인 스레드가 밀려 예약이 늦게 돌아도 음수 지연이 나오지 않는다.
        #expect(Schedule.delay(now: 2.0, firstSignal: 0, debounce: 0.5, maxWait: 1.5) == 0)
    }

    @Test func 폭주가_이어지는_동안에도_갱신이_계속_흐른다() {
        // FSEvents 배치가 0.3초마다 끝없이 오는 실제 폭주(npm install)를 6초간 재현한다.
        // 트레일링만 있던 옛 코드에선 재예약이 무한 반복돼 flush가 **0번**이었다(패널이 얼어붙음).
        var firstSignal: TimeInterval?
        var scheduled: TimeInterval?
        var flushes: [TimeInterval] = []

        for step in 0..<20 {
            let now = Double(step) * 0.3
            if let fire = scheduled, fire <= now { // 예약이 이 배치보다 먼저 도착했다 → 갱신 1회
                flushes.append(fire)
                firstSignal = nil
                scheduled = nil
            }
            let first = firstSignal ?? now
            firstSignal = first
            scheduled = now + Schedule.delay(now: now, firstSignal: first,
                                             debounce: FileWatcher.debounce, maxWait: FileWatcher.maxWait)
        }

        #expect(flushes.count >= 3) // 폭주 중에도 상한 주기로 흐른다(옛 코드: 0)
        #expect(flushes[0] <= FileWatcher.maxWait + 0.0001) // 첫 갱신이 상한을 넘지 않는다
    }
}
