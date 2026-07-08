import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { TerminalPane } from "./TerminalPane";
import {
  type Dir,
  type Divider,
  type TreeNode,
  makePane,
  splitPane,
  closePane,
  setSplitSizes,
  computeLayout,
  collectPaneIds,
  firstPaneId,
  siblingPaneId,
} from "./tree";

const MIN_FRAC = 0.05; // 패인 최소 크기(분할 축 대비 5%)

function App() {
  const [tree, setTree] = useState<TreeNode>(() => makePane());
  const [focusedId, setFocusedId] = useState<string>(() => firstPaneId(tree));
  const [dragCursor, setDragCursor] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

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

  // 구분선 드래그 → 인접 두 자식 사이에서 가중치를 이동
  const startDrag = useCallback((d: Divider, e: React.MouseEvent) => {
    const cont = containerRef.current;
    if (!cont) return;
    e.preventDefault();
    const contRect = cont.getBoundingClientRect();
    const axisPx = (d.axisPct / 100) * (d.dir === "row" ? contRect.width : contRect.height);
    if (axisPx <= 0) return;

    const total = d.sizes.reduce((a, b) => a + b, 0);
    const minSize = total * MIN_FRAC;
    const startSizes = d.sizes;
    const startPointer = d.dir === "row" ? e.clientX : e.clientY;
    const i = d.index;

    setDragCursor(d.dir === "row" ? "col-resize" : "row-resize");

    const onMove = (ev: MouseEvent) => {
      const cur = d.dir === "row" ? ev.clientX : ev.clientY;
      const deltaWeight = ((cur - startPointer) / axisPx) * total;
      let a = startSizes[i] + deltaWeight;
      let b = startSizes[i + 1] - deltaWeight;
      if (a < minSize) {
        b -= minSize - a;
        a = minSize;
      }
      if (b < minSize) {
        a -= minSize - b;
        b = minSize;
      }
      const newSizes = [...startSizes];
      newSizes[i] = a;
      newSizes[i + 1] = b;
      setTree((prev) => setSplitSizes(prev, d.splitId, newSizes));
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      setDragCursor(null);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  }, []);

  const layout = useMemo(() => computeLayout(tree), [tree]);
  const paneIds = useMemo(() => collectPaneIds(tree), [tree]);

  return (
    <div ref={containerRef} style={{ position: "relative", height: "100%", width: "100%", background: "var(--bg)" }}>
      {paneIds.map((id) => {
        const r = layout.panes.get(id)!;
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

      {layout.dividers.map((d) => (
        <div
          key={d.key}
          className="divider"
          onMouseDown={(e) => startDrag(d, e)}
          style={
            d.dir === "row"
              ? {
                  position: "absolute",
                  left: `calc(${d.pos}% - 3px)`,
                  top: `${d.cross}%`,
                  width: 6,
                  height: `${d.crossSize}%`,
                  cursor: "col-resize",
                }
              : {
                  position: "absolute",
                  top: `calc(${d.pos}% - 3px)`,
                  left: `${d.cross}%`,
                  height: 6,
                  width: `${d.crossSize}%`,
                  cursor: "row-resize",
                }
          }
        />
      ))}

      {/* 드래그 중 전면 오버레이 — xterm이 마우스를 가로채지 않도록 + 커서 고정 */}
      {dragCursor && (
        <div style={{ position: "fixed", inset: 0, zIndex: 9999, cursor: dragCursor }} />
      )}
    </div>
  );
}

export default App;
