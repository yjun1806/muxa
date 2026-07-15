import Bonsplit
import Foundation

/// 분할 트리를 "모든 칸이 같은 크기"가 되도록 각 divider 위치를 계산하는 순수 로직.
///
/// 각 split의 divider는 **양쪽 서브트리의 칸(리프) 개수 비율**로 놓는다 — 왼쪽 서브트리에
/// 칸이 a개, 오른쪽에 b개면 divider = a/(a+b). 이렇게 하면 트리 모양과 무관하게 모든 칸이
/// 같은 면적을 갖는다. 좌우 분할만 있으면 곧 모든 칸이 **같은 너비**가 된다
/// (muxa의 흔한 나란히-보기 케이스). 부작용 없음 — 뷰·컨트롤러를 모른다.
enum SplitEqualize {
    /// 트리를 걸어 각 split에 매길 divider 위치를 `(splitId, position)`로 모은다.
    /// 단일 칸(리프)이면 빈 배열 — 조정할 divider가 없다.
    static func positions(for node: ExternalTreeNode) -> [(splitId: UUID, position: CGFloat)] {
        switch node {
        case .pane:
            return []
        case .split(let s):
            let a = leafCount(s.first)
            let b = leafCount(s.second)
            var result: [(splitId: UUID, position: CGFloat)] = []
            if let id = UUID(uuidString: s.id), a + b > 0 {
                result.append((id, CGFloat(a) / CGFloat(a + b)))
            }
            result += positions(for: s.first)
            result += positions(for: s.second)
            return result
        }
    }

    /// 서브트리에 든 칸(리프)의 개수.
    static func leafCount(_ node: ExternalTreeNode) -> Int {
        switch node {
        case .pane:
            return 1
        case .split(let s):
            return leafCount(s.first) + leafCount(s.second)
        }
    }
}
