import Foundation

/// 서브탭 분리·병합의 **판정만** 담는 순수 로직 — 부작용(패인 분할·탭 이동)은 `TerminalStore`가 한다.
/// 무엇을 할 수 있는지(분리 가능 여부·병합 대상)를 UI 없이 검증할 수 있게 값만 받아 값만 낸다.
enum GroupSplitPlan {
    /// 이 서브탭을 새 패인으로 분리할 수 있나 — 그룹에 항목이 **둘 이상**일 때만.
    /// 하나뿐이면 분리는 그룹 탭을 통째로 옮기는 것과 같아 의미가 없다(그냥 탭 드래그로 족하다).
    static func canDetach(itemCount: Int) -> Bool { itemCount > 1 }

    /// 병합 대상 그룹 탭들 — 같은 종류이고 **다른 패인**에 있는 것만("단 같은 그룹만").
    /// 같은 패인엔 종류별 그룹이 하나뿐이라(불변식) 자기 자신 말곤 후보가 없다.
    static func mergeTargets<Tab: Hashable, Pane: Equatable>(
        sourceTab: Tab, sourceKind: TabGroupKind, sourcePane: Pane,
        candidates: [(tab: Tab, kind: TabGroupKind, pane: Pane)]
    ) -> [Tab] {
        candidates
            .filter { $0.kind == sourceKind && $0.pane != sourcePane && $0.tab != sourceTab }
            .map(\.tab)
    }
}
