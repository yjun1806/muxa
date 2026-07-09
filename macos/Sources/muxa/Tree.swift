// 분할 트리 모델과 순수 변환 함수들. (src/tree.ts의 Swift 이식)
// 렌더는 이 트리에서 각 패인의 사각형(%)만 계산해 평면·절대위치로 그린다 —
// 그래야 트리가 재구성돼도 패인(서피스/PTY)이 재생성되지 않는다.
// 모든 노드는 고유 id를 가진다(뷰 식별 안정성 + 리사이즈 대상 식별).

import Foundation

/// row: 좌우 나란히(세로 분할) / col: 위아래(가로 분할)
enum Dir {
    case row
    case col
}

indirect enum TreeNode {
    case pane(id: String)
    case split(id: String, dir: Dir, children: [TreeNode], sizes: [Double])

    var id: String {
        switch self {
        case let .pane(id): return id
        case let .split(id, _, _, _): return id
        }
    }
}

func newId() -> String {
    UUID().uuidString
}

func makePane(id: String = newId()) -> TreeNode {
    .pane(id: id)
}

/// 트리 순회 순서대로 패인 id 목록 (포커스 순환·복원에 사용).
func collectPaneIds(_ node: TreeNode) -> [String] {
    switch node {
    case let .pane(id): return [id]
    case let .split(_, _, children, _): return children.flatMap(collectPaneIds)
    }
}

func firstPaneId(_ node: TreeNode) -> String {
    switch node {
    case let .pane(id): return id
    case let .split(_, _, children, _): return firstPaneId(children[0])
    }
}

/// 포커스를 트리 순서로 delta칸 이동한 패인 id.
func siblingPaneId(_ tree: TreeNode, focusedId: String, delta: Int) -> String {
    let ids = collectPaneIds(tree)
    guard let i = ids.firstIndex(of: focusedId) else { return ids[0] }
    let n = ids.count
    return ids[((i + delta) % n + n) % n]
}

struct Rect: Equatable {
    var left: Double
    var top: Double
    var width: Double
    var height: Double
}

/// 구분선 하나 — 분할 노드의 child[index]와 child[index+1] 사이 경계(모두 % 단위).
struct Divider: Equatable {
    var key: String
    var splitId: String
    var index: Int
    var dir: Dir
    var pos: Double // 축 방향 경계 위치(%)
    var cross: Double // 교차축 시작(%)
    var crossSize: Double // 교차축 길이(%)
    var axisPct: Double // 이 분할 노드의 축 길이(%) — px 변환용
    var sizes: [Double] // 분할 노드의 현재 sizes 스냅샷
}

struct Layout {
    var panes: [String: Rect] = [:]
    var dividers: [Divider] = []
}

/// 트리를 패인 사각형(%)과 구분선 목록으로 펼친다.
func computeLayout(_ node: TreeNode) -> Layout {
    var acc = Layout()
    computeLayout(node, rect: Rect(left: 0, top: 0, width: 100, height: 100), into: &acc)
    return acc
}

private func computeLayout(_ node: TreeNode, rect: Rect, into acc: inout Layout) {
    switch node {
    case let .pane(id):
        acc.panes[id] = rect
    case let .split(id, dir, children, sizes):
        let total = sizes.reduce(0, +)
        let axisLen = dir == .row ? rect.width : rect.height
        var offset = 0.0
        for (i, child) in children.enumerated() {
            let span = (sizes[i] / total) * axisLen
            let childRect =
                dir == .row
                    ? Rect(left: rect.left + offset, top: rect.top, width: span, height: rect.height)
                    : Rect(left: rect.left, top: rect.top + offset, width: rect.width, height: span)
            offset += span
            computeLayout(child, rect: childRect, into: &acc)
            // 마지막 자식 뒤에는 구분선이 없다
            if i < children.count - 1 {
                acc.dividers.append(Divider(
                    key: "\(id):\(i)",
                    splitId: id,
                    index: i,
                    dir: dir,
                    pos: dir == .row ? rect.left + offset : rect.top + offset,
                    cross: dir == .row ? rect.top : rect.left,
                    crossSize: dir == .row ? rect.height : rect.width,
                    axisPct: axisLen,
                    sizes: sizes
                ))
            }
        }
    }
}

/// 분할 노드의 sizes를 교체한다(구분선 드래그).
func setSplitSizes(_ node: TreeNode, splitId: String, sizes: [Double]) -> TreeNode {
    switch node {
    case .pane:
        return node
    case let .split(id, dir, children, currentSizes):
        if id == splitId {
            return .split(id: id, dir: dir, children: children, sizes: sizes)
        }
        return .split(
            id: id, dir: dir,
            children: children.map { setSplitSizes($0, splitId: splitId, sizes: sizes) },
            sizes: currentSizes
        )
    }
}

/// 포커스된 패인을 dir 방향으로 분할한다.
/// 부모가 같은 방향이면 형제로 추가(균등 분할), 아니면 새 분할 노드로 감싼다.
/// 반환: 새 트리 + 새로 생긴 패인 id.
func splitPane(_ tree: TreeNode, targetId: String, dir: Dir) -> (tree: TreeNode, newPaneId: String) {
    let newPaneId = newId()
    return (insert(tree, targetId: targetId, dir: dir, newPaneId: newPaneId), newPaneId)
}

private func insert(_ node: TreeNode, targetId: String, dir: Dir, newPaneId: String) -> TreeNode {
    switch node {
    case let .pane(id):
        if id != targetId { return node }
        // 부모 컨텍스트를 모르는 경우(루트가 패인 등): 새 분할 노드로 감싼다
        return .split(id: newId(), dir: dir, children: [node, makePane(id: newPaneId)], sizes: [50, 50])

    case let .split(id, nodeDir, children, sizes):
        // 같은 방향 분할이고 대상이 직속 패인 자식이면 형제로 추가한다(중첩 대신 균등)
        let idx = children.firstIndex { child in
            if case let .pane(cid) = child { return cid == targetId }
            return false
        }
        if let idx, nodeDir == dir {
            let half = sizes[idx] / 2
            var newChildren = children
            newChildren.insert(makePane(id: newPaneId), at: idx + 1)
            var newSizes = sizes
            newSizes.replaceSubrange(idx ... idx, with: [half, half])
            return .split(id: id, dir: nodeDir, children: newChildren, sizes: newSizes)
        }
        // 그 외: 자식으로 재귀 (매칭된 패인은 pane 케이스에서 감싸진다)
        return .split(
            id: id, dir: nodeDir,
            children: children.map { insert($0, targetId: targetId, dir: dir, newPaneId: newPaneId) },
            sizes: sizes
        )
    }
}

/// 패인을 닫는다. 부모가 자식 하나만 남으면 그 자식으로 대체(collapse).
/// 마지막 패인은 닫지 않는다(항상 ≥1 패인 유지).
func closePane(_ tree: TreeNode, targetId: String) -> TreeNode {
    removeFrom(tree, targetId: targetId) ?? tree
}

private func removeFrom(_ node: TreeNode, targetId: String) -> TreeNode? {
    switch node {
    case let .pane(id):
        return id == targetId ? nil : node
    case let .split(id, dir, children, sizes):
        var newChildren: [TreeNode] = []
        var newSizes: [Double] = []
        for (i, child) in children.enumerated() {
            if let r = removeFrom(child, targetId: targetId) {
                newChildren.append(r)
                newSizes.append(sizes[i])
            }
        }
        if newChildren.isEmpty { return nil }
        if newChildren.count == 1 { return newChildren[0] } // collapse
        return .split(id: id, dir: dir, children: newChildren, sizes: newSizes)
    }
}
