import XCTest

@testable import muxa

final class TreeTests: XCTestCase {
    // 분할 노드의 자식 수(중첩 여부 판별용)
    private func childCount(_ node: TreeNode) -> Int {
        if case let .split(_, _, children, _) = node { return children.count }
        return 0
    }

    func testRootPaneSplitWrapsInSplitNode() {
        let root = makePane()
        let (tree, newId) = splitPane(root, targetId: root.id, dir: .row)
        // 루트 패인 → split(자식 2)로 감싸짐
        XCTAssertEqual(childCount(tree), 2)
        XCTAssertEqual(collectPaneIds(tree).count, 2)
        XCTAssertTrue(collectPaneIds(tree).contains(newId))
        if case let .split(_, dir, _, sizes) = tree {
            XCTAssertEqual(dir, .row)
            XCTAssertEqual(sizes, [50, 50])
        } else {
            XCTFail("split 노드가 아님")
        }
    }

    func testSameDirectionAddsSiblingNotNesting() {
        let root = makePane()
        let (t1, _) = splitPane(root, targetId: root.id, dir: .row)
        let ids = collectPaneIds(t1)
        // 같은 방향으로 재분할 → 중첩 없이 형제로 추가(자식 3)
        let (t2, _) = splitPane(t1, targetId: ids[0], dir: .row)
        XCTAssertEqual(childCount(t2), 3)
        XCTAssertEqual(collectPaneIds(t2).count, 3)
        // 균등 재분배: 첫 패인 50 → 25/25
        if case let .split(_, _, _, sizes) = t2 {
            XCTAssertEqual(sizes[0], 25)
            XCTAssertEqual(sizes[1], 25)
            XCTAssertEqual(sizes[2], 50)
        }
    }

    func testDifferentDirectionNests() {
        let root = makePane()
        let (t1, _) = splitPane(root, targetId: root.id, dir: .row)
        let ids = collectPaneIds(t1)
        // 다른 방향 분할 → 해당 패인이 새 split으로 감싸짐(중첩)
        let (t2, _) = splitPane(t1, targetId: ids[0], dir: .col)
        XCTAssertEqual(childCount(t2), 2) // 최상위는 여전히 자식 2
        XCTAssertEqual(collectPaneIds(t2).count, 3)
        if case let .split(_, _, children, _) = t2 {
            XCTAssertEqual(childCount(children[0]), 2) // 첫 자식이 중첩 split
        }
    }

    func testClosePaneCollapsesParent() {
        let root = makePane()
        let (t1, newId) = splitPane(root, targetId: root.id, dir: .row)
        // 새 패인을 닫으면 split이 붕괴되어 남은 패인이 루트가 됨
        let t2 = closePane(t1, targetId: newId)
        XCTAssertEqual(collectPaneIds(t2).count, 1)
        if case .pane = t2 {} else { XCTFail("collapse 후 단일 패인이어야 함") }
    }

    func testCannotCloseLastPane() {
        let root = makePane()
        let t = closePane(root, targetId: root.id)
        // 마지막 패인은 닫히지 않는다
        XCTAssertEqual(collectPaneIds(t).count, 1)
    }

    func testComputeLayoutRowSplit() {
        let root = makePane()
        let (tree, _) = splitPane(root, targetId: root.id, dir: .row)
        let layout = computeLayout(tree)
        XCTAssertEqual(layout.panes.count, 2)
        XCTAssertEqual(layout.dividers.count, 1)
        // row 분할: 두 패인이 좌우로 각 50% 폭, 전체 높이
        let rects = layout.panes.values.sorted { $0.left < $1.left }
        XCTAssertEqual(rects[0], Rect(left: 0, top: 0, width: 50, height: 100))
        XCTAssertEqual(rects[1], Rect(left: 50, top: 0, width: 50, height: 100))
    }

    func testSiblingPaneIdCycles() {
        let root = makePane()
        let (t1, _) = splitPane(root, targetId: root.id, dir: .row)
        let ids = collectPaneIds(t1)
        XCTAssertEqual(siblingPaneId(t1, focusedId: ids[0], delta: 1), ids[1])
        XCTAssertEqual(siblingPaneId(t1, focusedId: ids[1], delta: 1), ids[0]) // 순환
        XCTAssertEqual(siblingPaneId(t1, focusedId: ids[0], delta: -1), ids[1]) // 역방향 순환
    }

    func testSetSplitSizes() {
        let root = makePane()
        let (tree, _) = splitPane(root, targetId: root.id, dir: .row)
        let updated = setSplitSizes(tree, splitId: tree.id, sizes: [70, 30])
        if case let .split(_, _, _, sizes) = updated {
            XCTAssertEqual(sizes, [70, 30])
        } else {
            XCTFail("split 노드여야 함")
        }
    }
}
