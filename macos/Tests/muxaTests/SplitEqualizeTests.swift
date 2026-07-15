import Foundation
import Testing
import Bonsplit
@testable import muxa

/// divider 더블클릭 → 모든 칸 균등화의 순수 판정. 각 split divider를 양쪽 칸 개수 비율로.
struct SplitEqualizeTests {
    private let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)

    /// divider 위치를 근사 비교(2/3·1/3은 이진 무한소수라 정확 비교가 취약).
    private func near(_ a: CGFloat?, _ b: CGFloat) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 1e-9
    }

    /// 리프 칸 — id로 구분한다(테스트에선 divider 계산에 안 쓰이지만 트리 구성용).
    private func pane(_ id: String = "p") -> ExternalTreeNode {
        .pane(ExternalPaneNode(id: id, frame: zero, tabs: [], selectedTabId: nil))
    }

    /// split 노드 — id는 divider 매핑에 쓰이므로 유효한 UUID 문자열로.
    private func split(_ id: UUID, _ orient: String, _ first: ExternalTreeNode, _ second: ExternalTreeNode) -> ExternalTreeNode {
        .split(ExternalSplitNode(id: id.uuidString, orientation: orient, dividerPosition: 0.9,
                                 first: first, second: second))
    }

    @Test("단일 칸이면 조정할 divider가 없다")
    func 단일칸() {
        #expect(SplitEqualize.positions(for: pane()).isEmpty)
    }

    @Test("좌우 2칸이면 divider는 0.5")
    func 좌우2칸() {
        let id = UUID()
        let tree = split(id, "horizontal", pane("a"), pane("b"))
        let out = SplitEqualize.positions(for: tree)
        #expect(out.count == 1)
        #expect(out[0].splitId == id)
        #expect(out[0].position == 0.5)
    }

    @Test("좌우 3칸 ((a|b)|c)이면 바깥 divider는 2/3, 안쪽은 1/2 — 세 칸 모두 1/3 너비")
    func 좌우3칸_왼쪽으로중첩() {
        let outer = UUID(); let inner = UUID()
        let tree = split(outer, "horizontal", split(inner, "horizontal", pane("a"), pane("b")), pane("c"))
        let out = Dictionary(uniqueKeysWithValues: SplitEqualize.positions(for: tree).map { ($0.splitId, $0.position) })
        #expect(near(out[outer], 2.0 / 3.0))
        #expect(near(out[inner], 0.5))
    }

    @Test("세로 분할이 섞여도 칸 개수 비율은 동일 — 면적이 같아진다")
    func 세로혼합() {
        // a | (b / c)  →  왼쪽 1칸 : 오른쪽 2칸
        let outer = UUID(); let inner = UUID()
        let tree = split(outer, "horizontal", pane("a"), split(inner, "vertical", pane("b"), pane("c")))
        let out = Dictionary(uniqueKeysWithValues: SplitEqualize.positions(for: tree).map { ($0.splitId, $0.position) })
        #expect(near(out[outer], 1.0 / 3.0))   // a는 전체의 1/3
        #expect(near(out[inner], 0.5))         // b·c는 오른쪽 2/3를 반씩
    }

    @Test("leafCount는 트리의 모든 칸을 센다")
    func 리프개수() {
        let tree = split(UUID(), "horizontal",
                         split(UUID(), "vertical", pane(), pane()),
                         split(UUID(), "horizontal", pane(), pane()))
        #expect(SplitEqualize.leafCount(tree) == 4)
    }
}
