import Testing
@testable import muxa

/// 서브탭 분리·병합 판정(순수) — 부작용 없이 "무엇을 할 수 있나"만 검증한다.
struct GroupSplitPlanTests {
    // 테스트용 후보 튜플 — (탭, 종류, 패인)을 Int로 흉내낸다.
    private func ref(_ tab: Int, _ kind: TabGroupKind, _ pane: Int) -> (tab: Int, kind: TabGroupKind, pane: Int) {
        (tab, kind, pane)
    }

    @Test func 항목이_둘_이상일_때만_분리() {
        #expect(GroupSplitPlan.canDetach(itemCount: 2))
        #expect(GroupSplitPlan.canDetach(itemCount: 5))
    }

    @Test func 항목이_하나_이하면_분리_불가() {
        #expect(!GroupSplitPlan.canDetach(itemCount: 1))
        #expect(!GroupSplitPlan.canDetach(itemCount: 0))
    }

    @Test func 병합은_같은_종류_다른_패인만() {
        let candidates = [
            ref(1, .documents, 10), // source 자신
            ref(2, .documents, 20), // ✓ 같은 종류·다른 패인
            ref(3, .code, 20),      // ✗ 다른 종류
            ref(4, .documents, 10), // ✗ 같은 패인(불변식상 실제론 안 생기지만 방어)
        ]
        let targets = GroupSplitPlan.mergeTargets(
            sourceTab: 1, sourceKind: .documents, sourcePane: 10, candidates: candidates)
        #expect(targets == [2])
    }

    @Test func 자기_자신은_병합_대상이_아니다() {
        let candidates = [ref(1, .documents, 10)]
        let targets = GroupSplitPlan.mergeTargets(
            sourceTab: 1, sourceKind: .documents, sourcePane: 10, candidates: candidates)
        #expect(targets.isEmpty)
    }

    @Test func 대상이_없으면_빈_목록() {
        let candidates = [ref(2, .code, 20), ref(3, .diffs, 30)]
        let targets = GroupSplitPlan.mergeTargets(
            sourceTab: 1, sourceKind: .documents, sourcePane: 10, candidates: candidates)
        #expect(targets.isEmpty)
    }

    @Test func 여러_패인의_같은_종류는_모두_대상() {
        let candidates = [
            ref(1, .documents, 10), // source
            ref(2, .documents, 20), // ✓
            ref(3, .documents, 30), // ✓
        ]
        let targets = GroupSplitPlan.mergeTargets(
            sourceTab: 1, sourceKind: .documents, sourcePane: 10, candidates: candidates)
        #expect(targets == [2, 3])
    }
}
