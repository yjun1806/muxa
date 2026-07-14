import Testing
@testable import muxa

/// 프로젝트 닫기 판정(순수) — 파괴적 동작이라 조건을 테스트로 못 박는다.
struct ProjectCloseTests {
    @Test func 메인_창의_프로젝트는_묻지_않고_닫는다() {
        #expect(ProjectCloseDecision.decide(separated: false) == .closeNow)
    }

    @Test func 분리_창의_프로젝트는_확인을_받는다() {
        // 화면 밖에서 돌고 있는 에이전트·dev 서버를 ✕ 한 번으로 몰살시키지 않는다.
        #expect(ProjectCloseDecision.decide(separated: true) == .confirm)
    }
}
