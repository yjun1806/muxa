import Foundation

/// 세션 스냅샷 복원 방어 상한 — 순수 로직(부작용 없음, 새 값 생성).
/// 손상되거나 비정상적으로 비대한 스냅샷(예: 버그로 탭이 폭증, 파일 변조)이 복원 폭주를 일으키지
/// 않도록 리프당 탭 수·분할 트리 깊이·탭당 서브탭 수에 합리적 상한을 두고, 선택 인덱스·분할 비율을
/// 안전 범위로 clamp한다. 명시적 version 필드와 함께 비대화·손상 방어의 기준점이 된다.
enum SnapshotSanitize {
    /// 한 칸(leaf)에 허용하는 최대 탭 수.
    static let maxTabsPerLeaf = 64
    /// 분할 트리 최대 깊이(중첩 split) — 초과 시 더 내려가지 않고 first 서브트리로 평면화.
    static let maxDepth = 16
    /// 그룹 탭 하나의 최대 서브탭 수.
    static let maxItemsPerTab = 128
    /// 분할 비율 안전 범위 — 퇴화(0/1)로 칸이 사라지지 않게.
    static let minDivider = 0.05
    static let maxDivider = 0.95

    /// 스냅샷을 상한에 맞춰 정제한 새 스냅샷을 반환한다. 초과분은 잘라내고 인덱스·비율은 범위로 clamp.
    static func clamp(_ snap: PaneSnapshot, depth: Int = 0) -> PaneSnapshot {
        switch snap {
        case .leaf(let tabs, let selected, let focused):
            let capped = Array(tabs.prefix(maxTabsPerLeaf)).map(clampTab)
            let safeSelected = capped.isEmpty ? 0 : min(max(selected, 0), capped.count - 1)
            return .leaf(tabs: capped, selected: safeSelected, focused: focused)
        case .split(let vertical, let divider, let first, let second):
            // 깊이 초과 시 더 내려가지 않고 first 서브트리만 정제해 평면화(과다 중첩 방어).
            guard depth < maxDepth else { return clamp(first, depth: depth) }
            let safeDivider = min(max(divider, minDivider), maxDivider)
            return .split(vertical: vertical, divider: safeDivider,
                          first: clamp(first, depth: depth + 1),
                          second: clamp(second, depth: depth + 1))
        }
    }

    /// 탭당 서브탭 상한 적용 + 선택 서브탭 인덱스 clamp(불변 — 초과 없으면 원본 그대로).
    private static func clampTab(_ tab: TabSnapshot) -> TabSnapshot {
        guard tab.items.count > maxItemsPerTab else { return tab }
        var next = tab
        next.items = Array(tab.items.prefix(maxItemsPerTab))
        next.selectedItem = min(max(tab.selectedItem, 0), next.items.count - 1)
        return next
    }

    /// 프로젝트별 스냅샷 맵 전체를 정제한 새 맵을 반환한다. AppState.load가 복원 직전에 통과시킨다.
    static func clampAll(_ layouts: [String: PaneSnapshot]) -> [String: PaneSnapshot] {
        layouts.mapValues { clamp($0) }
    }
}
