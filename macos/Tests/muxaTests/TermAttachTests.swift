import Testing
@testable import muxa

/// 서피스 재부모화 판정(순수) — 창 간 쟁탈 차단(I3)과 기존 회귀 방어(hold).
struct TermAttachTests {
    @Test func 소유자가_아니면_붙지_않는다() {
        // 메인의 죽어가는 뷰 트리가 나중에 돌아도 분리 창의 터미널을 뺏어가면 안 된다.
        #expect(TermAttach.decide(isOwner: false, alreadyChild: false,
                                  containerInWindow: true, termInWindow: true) == .skip)
    }

    @Test func 이미_자식이면_아무것도_안_한다() {
        #expect(TermAttach.decide(isOwner: true, alreadyChild: true,
                                  containerInWindow: true, termInWindow: true) == .skip)
    }

    @Test func 컨테이너가_창에_있으면_언제나_붙는다() {
        #expect(TermAttach.decide(isOwner: true, alreadyChild: false,
                                  containerInWindow: true, termInWindow: true) == .attach)
        #expect(TermAttach.decide(isOwner: true, alreadyChild: false,
                                  containerInWindow: true, termInWindow: false) == .attach)
    }

    @Test func 화면_밖_컨테이너는_산_터미널을_뺏지_않는다() {
        // 창을 잃은(=죽어가는) 계층이 화면에 붙어 있는 터미널을 끌어가면 흰 화면이 된다.
        #expect(TermAttach.decide(isOwner: true, alreadyChild: false,
                                  containerInWindow: false, termInWindow: true) == .hold)
    }

    @Test func 둘_다_창_밖이면_붙는다() {
        // 아직 창에 올라가기 전(첫 makeNSView) — 뺏을 게 없으니 미리 붙여 둔다.
        #expect(TermAttach.decide(isOwner: true, alreadyChild: false,
                                  containerInWindow: false, termInWindow: false) == .attach)
    }
}
