import Testing
import Foundation
@testable import muxa

/// 복원한 창 프레임이 실제로 **사용자가 잡을 수 있는 위치**인가(순수).
///
/// 외장 모니터에서 쓰던 좌표를 그대로 복원하면 모니터를 뽑은 뒤엔 창이 화면 밖에 뜬다.
/// AppKit이 알아서 보정해 주지 않는다 — 창이 통째로 안 보이는 회귀를 실제로 냈다.
struct WindowFrameTests {
    /// 1440x900 단일 화면(원점 0,0).
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func 화면_안의_창은_잡을_수_있다() {
        let frame = NSRect(x: 100, y: 100, width: 1000, height: 680)
        #expect(WindowFrame.isReachable(frame, screens: [screen]))
    }

    @Test func 화면_밖_창은_잡을_수_없다() {
        // 외장 모니터를 뽑은 뒤 남은 옛 좌표 — 이게 이번 회귀의 실제 케이스다.
        let frame = NSRect(x: -192, y: 2460, width: 1400, height: 820)
        #expect(!WindowFrame.isReachable(frame, screens: [screen]))
    }

    @Test func 타이틀바가_화면_위로_벗어나면_잡을_수_없다() {
        // 본문 일부가 겹쳐도 타이틀바가 화면 위로 나가면 드래그로 되찾을 수 없다.
        let frame = NSRect(x: 200, y: 880, width: 1000, height: 680)
        #expect(!WindowFrame.isReachable(frame, screens: [screen]))
    }

    @Test func 살짝만_걸치면_잡을_수_없다() {
        // 오른쪽 끝에 20pt만 걸친 창 — 타이틀바를 붙잡을 폭이 안 나온다.
        let frame = NSRect(x: 1420, y: 400, width: 1000, height: 680)
        #expect(!WindowFrame.isReachable(frame, screens: [screen]))
    }

    @Test func 외장_모니터가_붙어_있으면_그_좌표도_유효하다() {
        let external = NSRect(x: -361, y: 1600, width: 3360, height: 1860)
        let frame = NSRect(x: -192, y: 2460, width: 1400, height: 820)
        #expect(WindowFrame.isReachable(frame, screens: [screen, external]))
    }

    @Test func 화면이_하나도_없으면_잡을_수_없다() {
        #expect(!WindowFrame.isReachable(NSRect(x: 0, y: 0, width: 100, height: 100), screens: []))
    }
}
