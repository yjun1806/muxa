import { SquareSplitHorizontal, SquareSplitVertical, X } from "lucide-react";
import type { Dir } from "./tree";

interface Props {
  onSplit: (dir: Dir) => void;
  onClose: () => void;
}

/**
 * 패인별 헤더 — 그 패인을 직접 분할·닫는다.
 * 전역 툴바와 달리 "패인 선택 → 분할" 단계가 없다(각 영역이 자기 컨트롤을 가짐).
 */
export function PaneHeader({ onSplit, onClose }: Props) {
  return (
    <div className="pane-header">
      <button
        className="tool-btn"
        title="세로 분할 · 좌우 (⌘D)"
        aria-label="세로 분할"
        onClick={() => onSplit("row")}
      >
        <SquareSplitHorizontal size={13} strokeWidth={1.5} />
      </button>
      <button
        className="tool-btn"
        title="가로 분할 · 위아래 (⌘⇧D)"
        aria-label="가로 분할"
        onClick={() => onSplit("col")}
      >
        <SquareSplitVertical size={13} strokeWidth={1.5} />
      </button>
      <button
        className="tool-btn"
        title="패인 닫기 (⌘W)"
        aria-label="패인 닫기"
        onClick={onClose}
      >
        <X size={13} strokeWidth={1.5} />
      </button>
    </div>
  );
}
