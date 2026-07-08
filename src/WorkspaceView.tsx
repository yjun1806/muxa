import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { TerminalPane } from "./TerminalPane";
import {
  type Dir,
  type Divider,
  type TreeNode,
  splitPane,
  closePane,
  setSplitSizes,
  computeLayout,
  collectPaneIds,
  firstPaneId,
  siblingPaneId,
} from "./tree";

const MIN_FRAC = 0.05; // 패인 최소 크기(분할 축 대비 5%)

interface Props {
  tree: TreeNode;
  focusedId: string;
  active: boolean;
  cwd?: string;
  onChange: (tree: TreeNode, focusedId: string) => void;
}

/**
 * 워크스페이스 하나의 분할 터미널 트리를 렌더한다(controlled).
 * 비활성일 때도 unmount하지 않고 display:none으로 숨겨 세션(PTY)을 살려둔다.
 */
export function WorkspaceView({ tree, focusedId, active, cwd, onChange }: Props) {
  const [dragCursor, setDragCursor] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const splitById = useCallback(
    (id: string, dir: Dir) => {
      const { tree: next, newPaneId } = splitPane(tree, id, dir);
      onChange(next, newPaneId);
    },
    [tree, onChange],
  );

  const closeById = useCallback(
    (id: string) => {
      const next = closePane(tree, id);
      const nextFocused = collectPaneIds(next).includes(focusedId) ? focusedId : firstPaneId(next);
      onChange(next, nextFocused);
    },
    [tree, focusedId, onChange],
  );

  // 키바인딩은 활성 워크스페이스에서만 (⌘ 조합 = 앱 레이어)
  useEffect(() => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      const k = e.key.toLowerCase();
      if (k === "d") {
        e.preventDefault();
        e.stopPropagation();
        splitById(focusedId, e.shiftKey ? "col" : "row");
      } else if (k === "w") {
        e.preventDefault();
        e.stopPropagation();
        closeById(focusedId);
      } else if (k === "]") {
        e.preventDefault();
        e.stopPropagation();
        onChange(tree, siblingPaneId(tree, focusedId, 1));
      } else if (k === "[") {
        e.preventDefault();
        e.stopPropagation();
        onChange(tree, siblingPaneId(tree, focusedId, -1));
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [active, splitById, closeById, tree, focusedId, onChange]);

  // 구분선 드래그 → 인접 두 자식 사이에서 가중치 이동
  const startDrag = useCallback(
    (d: Divider, e: React.MouseEvent) => {
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
      const baseTree = tree; // 드래그 시작 시점 트리(이 분할의 sizes만 바뀐다)

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
        onChange(setSplitSizes(baseTree, d.splitId, newSizes), focusedId);
      };
      const onUp = () => {
        window.removeEventListener("mousemove", onMove);
        window.removeEventListener("mouseup", onUp);
        setDragCursor(null);
      };
      window.addEventListener("mousemove", onMove);
      window.addEventListener("mouseup", onUp);
    },
    [tree, focusedId, onChange],
  );

  const layout = useMemo(() => computeLayout(tree), [tree]);
  const paneIds = useMemo(() => collectPaneIds(tree), [tree]);

  return (
    <div
      ref={containerRef}
      style={{
        position: "relative",
        height: "100%",
        width: "100%",
        background: "var(--bg)",
        display: active ? "block" : "none",
      }}
    >
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
              cwd={cwd}
              focused={id === focusedId}
              onFocus={() => onChange(tree, id)}
              onSplit={(dir) => splitById(id, dir)}
              onClose={() => closeById(id)}
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

      {dragCursor && (
        <div style={{ position: "fixed", inset: 0, zIndex: 9999, cursor: dragCursor }} />
      )}
    </div>
  );
}
