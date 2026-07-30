import Foundation
import Testing
@testable import muxa

/// 기준선 커밋의 유효성 판정.
///
/// 위험한 것은 실패가 아니라 **오도**다 — rebase 뒤에도 기준선 객체는 reflog가 붙잡아 살아 있는데
/// 더는 `HEAD`의 조상이 아니다. 그 상태로 `git diff <base>`는 **성공하면서** 남의 커밋까지 섞인
/// diff를 낸다. 조용히 틀린 화면은 에러 화면보다 나쁘다.
struct BaselineResolveTests {
    private let base = "a3f21c9"
    private let fork = "b7c1e42"

    @Test func 살아있고_조상이면_그대로_쓴다() {
        #expect(BaselineResolve.decide(baseline: base, exists: true, isAncestor: true, mergeBase: nil)
                == .use(base))
    }

    /// 이게 이 판정의 존재 이유다 — 객체는 있는데 조상이 아니다(rebase·브랜치 전환).
    @Test func 조상이_아니면_분기점으로_강등한다() {
        #expect(BaselineResolve.decide(baseline: base, exists: true, isAncestor: false, mergeBase: fork)
                == .degradeToMergeBase(fork))
    }

    /// gc가 객체를 지웠다.
    @Test func 객체가_사라지면_HEAD로_강등한다() {
        #expect(BaselineResolve.decide(baseline: base, exists: false, isAncestor: false, mergeBase: fork)
                == .degradeToHead)
    }

    /// 조상도 아니고 공통 조상도 없다(무관한 히스토리로 갈아탔다).
    @Test func 공통_조상도_없으면_HEAD로_강등한다() {
        #expect(BaselineResolve.decide(baseline: base, exists: true, isAncestor: false, mergeBase: nil)
                == .degradeToHead)
        #expect(BaselineResolve.decide(baseline: base, exists: true, isAncestor: false, mergeBase: "")
                == .degradeToHead)
    }

    @Test func 기준선이_아직_없으면_HEAD다() {
        #expect(BaselineResolve.decide(baseline: nil, exists: true, isAncestor: true, mergeBase: nil)
                == .degradeToHead)
        #expect(BaselineResolve.decide(baseline: "", exists: true, isAncestor: true, mergeBase: nil)
                == .degradeToHead)
    }

    // MARK: 결정 → diff 인자·문구

    @Test func 강등하면_HEAD를_넘긴다() {
        #expect(BaselineResolve.revision(for: .use(base)) == base)
        #expect(BaselineResolve.revision(for: .degradeToMergeBase(fork)) == fork)
        #expect(BaselineResolve.revision(for: .degradeToHead) == "HEAD",
                "미커밋 변경만 보여주는 기존 동작으로 떨어진다")
    }

    /// 정상이면 침묵하고, **강등은 말한다** — 조용히 다른 걸 보여주지 않는다.
    @Test func 정상은_침묵하고_강등만_사유를_말한다() {
        #expect(BaselineResolve.notice(for: .use(base)) == nil)
        #expect(BaselineResolve.notice(for: .degradeToMergeBase(fork)) != nil)
        #expect(BaselineResolve.notice(for: .degradeToHead) != nil)
    }
}
