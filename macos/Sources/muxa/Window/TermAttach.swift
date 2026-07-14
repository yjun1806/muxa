/// 터미널 서피스(TermView)를 어느 컨테이너에 붙일지의 순수 판정.
///
/// 서피스는 창 사이를 옮겨 다니는 **공유 가변 자원**이다 — 두 창의 뷰 트리가 동시에
/// 자기 밑으로 끌어가면 살아 있는 터미널이 화면에서 사라진다. 판정만 여기로 떼어내 테스트한다.
enum TermAttach {
    enum Decision: Equatable { case skip, attach, hold }

    /// - isOwner=false → skip: 내 창이 소유한 term이 아니다(창 간 쟁탈 원천 차단).
    /// - alreadyChild → skip: 멱등.
    /// - containerInWindow → attach: 보이는 계층이 이긴다.
    /// - 컨테이너가 창 밖 + term은 창 안 → hold: 죽어가는 계층이 산 터미널을 뺏지 못하게(기존 회귀 방어).
    /// - 둘 다 창 밖 → attach: 뺏을 게 없다.
    ///
    /// `hold`는 **영구 포기가 아니다** — 컨테이너가 창을 얻는 순간 `viewDidMoveToWindow`가 다시 부른다.
    static func decide(isOwner: Bool,
                       alreadyChild: Bool,
                       containerInWindow: Bool,
                       termInWindow: Bool) -> Decision {
        guard isOwner else { return .skip }
        guard !alreadyChild else { return .skip }
        if containerInWindow { return .attach }
        return termInWindow ? .hold : .attach
    }
}
