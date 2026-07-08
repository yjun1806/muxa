import { useCallback, useEffect, useMemo, useState } from "react";
import { TerminalPane } from "./TerminalPane";
import {
  type Dir,
  type TreeNode,
  makePane,
  splitPane,
  closePane,
  computeLayout,
  collectPaneIds,
  firstPaneId,
  siblingPaneId,
} from "./tree";

function App() {
  const [tree, setTree] = useState<TreeNode>(() => makePane());
  const [focusedId, setFocusedId] = useState<string>(() => firstPaneId(tree));

  // 특정 패인을 직접 분할한다(패인 헤더 버튼이 자기 id로 호출).
  const splitPaneById = useCallback(
    (id: string, dir: Dir) => {
      const { tree: next, newPaneId } = splitPane(tree, id, dir);
      setTree(next);
      setFocusedId(newPaneId);
    },
    [tree],
  );

  const closePaneById = useCallback(
    (id: string) => {
      const next = closePane(tree, id);
      setTree(next);
      if (!collectPaneIds(next).includes(focusedId)) {
        setFocusedId(firstPaneId(next));
      }
    },
    [tree, focusedId],
  );

  // 키바인딩은 포커스된 패인을 대상으로 (⌘ 조합은 앱 레이어 — 터미널 Ctrl/vim과 충돌 없음)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      const k = e.key.toLowerCase();
      if (k === "d") {
        e.preventDefault();
        e.stopPropagation();
        splitPaneById(focusedId, e.shiftKey ? "col" : "row");
      } else if (k === "w") {
        e.preventDefault();
        e.stopPropagation();
        closePaneById(focusedId);
      } else if (k === "]") {
        e.preventDefault();
        e.stopPropagation();
        setFocusedId(siblingPaneId(tree, focusedId, 1));
      } else if (k === "[") {
        e.preventDefault();
        e.stopPropagation();
        setFocusedId(siblingPaneId(tree, focusedId, -1));
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [splitPaneById, closePaneById, tree, focusedId]);

  const layout = useMemo(() => computeLayout(tree), [tree]);
  const paneIds = useMemo(() => collectPaneIds(tree), [tree]);

  return (
    <div style={{ position: "relative", height: "100%", width: "100%", background: "var(--bg)" }}>
      {paneIds.map((id) => {
        const r = layout.get(id)!;
        return (
          <div
            key={id}
            style={{
              position: "absolute",
              left: `${r.left}%`,
              top: `${r.top}%`,
              width: `${r.width}%`,
              height: `${r.height}%`,
            }}
          >
            <TerminalPane
              paneId={id}
              focused={id === focusedId}
              onFocus={() => setFocusedId(id)}
              onSplit={(dir) => splitPaneById(id, dir)}
              onClose={() => closePaneById(id)}
            />
          </div>
        );
      })}
    </div>
  );
}

export default App;
