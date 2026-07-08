// 분할 트리 모델과 순수 변환 함수들.
// 렌더는 이 트리에서 각 패인의 사각형(%)만 계산해 평면·절대위치로 그린다 —
// 그래야 트리가 재구성돼도 패인(xterm/PTY)이 remount되지 않는다.
// 모든 노드는 고유 id를 가진다(React key 안정성 + 리사이즈 대상 식별).

export type Dir = "row" | "col"; // row: 좌우 나란히(세로 분할) / col: 위아래(가로 분할)

export type TreeNode =
  | { type: "pane"; id: string }
  | { type: "split"; id: string; dir: Dir; children: TreeNode[]; sizes: number[] };

export function newId(): string {
  return crypto.randomUUID();
}

export function makePane(id: string = newId()): TreeNode {
  return { type: "pane", id };
}

/** 트리 순회 순서대로 패인 id 목록 (포커스 순환·복원에 사용). */
export function collectPaneIds(node: TreeNode): string[] {
  return node.type === "pane" ? [node.id] : node.children.flatMap(collectPaneIds);
}

export function firstPaneId(node: TreeNode): string {
  return node.type === "pane" ? node.id : firstPaneId(node.children[0]);
}

/** 포커스를 트리 순서로 delta칸 이동한 패인 id. */
export function siblingPaneId(tree: TreeNode, focusedId: string, delta: number): string {
  const ids = collectPaneIds(tree);
  const i = ids.indexOf(focusedId);
  if (i === -1) return ids[0];
  return ids[(i + delta + ids.length) % ids.length];
}

export interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** 구분선 하나 — 분할 노드의 child[index]와 child[index+1] 사이 경계(모두 % 단위). */
export interface Divider {
  key: string;
  splitId: string;
  index: number;
  dir: Dir;
  pos: number; // 축 방향 경계 위치(%)
  cross: number; // 교차축 시작(%)
  crossSize: number; // 교차축 길이(%)
  axisPct: number; // 이 분할 노드의 축 길이(%) — px 변환용
  sizes: number[]; // 분할 노드의 현재 sizes 스냅샷
}

export interface Layout {
  panes: Map<string, Rect>;
  dividers: Divider[];
}

/** 트리를 패인 사각형(%)과 구분선 목록으로 펼친다. */
export function computeLayout(
  node: TreeNode,
  rect: Rect = { left: 0, top: 0, width: 100, height: 100 },
  acc: Layout = { panes: new Map(), dividers: [] },
): Layout {
  if (node.type === "pane") {
    acc.panes.set(node.id, rect);
    return acc;
  }
  const total = node.sizes.reduce((a, b) => a + b, 0);
  const axisLen = node.dir === "row" ? rect.width : rect.height;
  let offset = 0;
  node.children.forEach((child, i) => {
    const span = (node.sizes[i] / total) * axisLen;
    const childRect =
      node.dir === "row"
        ? { left: rect.left + offset, top: rect.top, width: span, height: rect.height }
        : { left: rect.left, top: rect.top + offset, width: rect.width, height: span };
    offset += span;
    computeLayout(child, childRect, acc);
    // 마지막 자식 뒤에는 구분선이 없다
    if (i < node.children.length - 1) {
      acc.dividers.push({
        key: `${node.id}:${i}`,
        splitId: node.id,
        index: i,
        dir: node.dir,
        pos: node.dir === "row" ? rect.left + offset : rect.top + offset,
        cross: node.dir === "row" ? rect.top : rect.left,
        crossSize: node.dir === "row" ? rect.height : rect.width,
        axisPct: axisLen,
        sizes: node.sizes,
      });
    }
  });
  return acc;
}

/** 분할 노드의 sizes를 교체한다(구분선 드래그). */
export function setSplitSizes(node: TreeNode, splitId: string, sizes: number[]): TreeNode {
  if (node.type === "pane") return node;
  if (node.id === splitId) return { ...node, sizes };
  return { ...node, children: node.children.map((c) => setSplitSizes(c, splitId, sizes)) };
}

/**
 * 포커스된 패인을 dir 방향으로 분할한다.
 * 부모가 같은 방향이면 형제로 추가(균등 분할), 아니면 새 분할 노드로 감싼다.
 * 반환: 새 트리 + 새로 생긴 패인 id.
 */
export function splitPane(
  tree: TreeNode,
  targetId: string,
  dir: Dir,
): { tree: TreeNode; newPaneId: string } {
  const newPaneId = newId();
  return { tree: insert(tree, targetId, dir, newPaneId), newPaneId };
}

function insert(node: TreeNode, targetId: string, dir: Dir, newPaneId: string): TreeNode {
  if (node.type === "pane") {
    if (node.id !== targetId) return node;
    // 부모 컨텍스트를 모르는 경우(루트가 패인 등): 새 분할 노드로 감싼다
    return {
      type: "split",
      id: newId(),
      dir,
      children: [node, makePane(newPaneId)],
      sizes: [50, 50],
    };
  }

  // 같은 방향 분할이고 대상이 직속 패인 자식이면 형제로 추가한다(중첩 대신 균등)
  const idx = node.children.findIndex((c) => c.type === "pane" && c.id === targetId);
  if (idx !== -1 && node.dir === dir) {
    const half = node.sizes[idx] / 2;
    return {
      ...node,
      children: [
        ...node.children.slice(0, idx + 1),
        makePane(newPaneId),
        ...node.children.slice(idx + 1),
      ],
      sizes: [...node.sizes.slice(0, idx), half, half, ...node.sizes.slice(idx + 1)],
    };
  }

  // 그 외: 자식으로 재귀 (매칭된 패인은 pane 케이스에서 감싸진다)
  return { ...node, children: node.children.map((c) => insert(c, targetId, dir, newPaneId)) };
}

/**
 * 패인을 닫는다. 부모가 자식 하나만 남으면 그 자식으로 대체(collapse).
 * 마지막 패인은 닫지 않는다(항상 ≥1 패인 유지).
 */
export function closePane(tree: TreeNode, targetId: string): TreeNode {
  return removeFrom(tree, targetId) ?? tree;
}

function removeFrom(node: TreeNode, targetId: string): TreeNode | null {
  if (node.type === "pane") {
    return node.id === targetId ? null : node;
  }
  const children: TreeNode[] = [];
  const sizes: number[] = [];
  node.children.forEach((c, i) => {
    const r = removeFrom(c, targetId);
    if (r !== null) {
      children.push(r);
      sizes.push(node.sizes[i]);
    }
  });
  if (children.length === 0) return null;
  if (children.length === 1) return children[0]; // collapse
  return { ...node, children, sizes };
}
