import Testing
@testable import muxa

/// 알림 게이트의 입력(I7) — "보인다"의 정의가 틀리면 알림이 통째로 억제되거나 통째로 새어 나온다.
struct WindowVisibilityTests {
    @Test func 앱이_비활성이면_보이지_않는_것으로_친다() {
        // 이게 빠지면 백그라운드에서도 visible=true가 되어 에이전트 완료 알림이 전면 억제된다.
        #expect(!WindowVisibility.isVisible(appActive: false, windowVisible: true,
                                            miniaturized: false, occluded: false))
    }

    @Test func key가_아니어도_화면에_보이면_보이는_것이다() {
        // 분리 창이 둘이면 하나만 key다 — key로 판정하면 옆 창의 보이는 탭에도 알림이 뜬다.
        #expect(WindowVisibility.isVisible(appActive: true, windowVisible: true,
                                           miniaturized: false, occluded: false))
    }

    @Test func 최소화된_창의_탭은_보이지_않는다() {
        #expect(!WindowVisibility.isVisible(appActive: true, windowVisible: true,
                                            miniaturized: true, occluded: false))
    }

    @Test func 완전히_가려지면_보이지_않는다() {
        #expect(!WindowVisibility.isVisible(appActive: true, windowVisible: true,
                                            miniaturized: false, occluded: true))
    }
}
