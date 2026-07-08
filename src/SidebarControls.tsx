import { Check, FolderOpen, Home, PanelLeft, Plus } from "lucide-react";
import { ICON } from "./icons";
import { type SidebarMode, SIDEBAR_MODES } from "./sidebarMode";

interface Props {
  mode: SidebarMode;
  onSetMode: (mode: SidebarMode) => void;
  onAddHome: () => void;
  onPick: () => void;
}

/**
 * 상단바의 사이드바 컨트롤 클러스터.
 * - 모드 버튼: hover 팝오버로 4개 표시 모드 선택
 * - 새 워크스페이스: 클릭=빠른 열기(홈), hover 팝오버로 [홈]/[폴더 선택] 분기
 * 팝오버는 CSS hover 기반(anchor 안에 버튼+팝오버가 함께 있어 이동 중에도 유지).
 */
export function SidebarControls({ mode, onSetMode, onAddHome, onPick }: Props) {
  return (
    <div className="controls">
      <div className="menu-anchor">
        <button className="tool-btn" title="사이드바 표시 모드" aria-label="사이드바 표시 모드">
          <PanelLeft {...ICON} />
        </button>
        <div className="menu-pop">
          <div className="menu-label">사이드바</div>
          {SIDEBAR_MODES.map((m) => (
            <button key={m.mode} className="menu-item" onClick={() => onSetMode(m.mode)}>
              <span className="menu-check">
                {mode === m.mode && <Check size={13} strokeWidth={2} />}
              </span>
              <span className="menu-text">{m.label}</span>
              <span className="menu-hint">{m.hint}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="menu-anchor">
        <button
          className="tool-btn"
          title="새 워크스페이스"
          aria-label="새 워크스페이스"
          onClick={onAddHome}
        >
          <Plus {...ICON} />
        </button>
        <div className="menu-pop">
          <div className="menu-label">새 워크스페이스</div>
          <button className="menu-item" onClick={onAddHome}>
            <span className="menu-check">
              <Home size={13} strokeWidth={1.5} />
            </span>
            <span className="menu-text">홈에서 열기</span>
          </button>
          <button className="menu-item" onClick={onPick}>
            <span className="menu-check">
              <FolderOpen size={13} strokeWidth={1.5} />
            </span>
            <span className="menu-text">폴더 선택…</span>
          </button>
        </div>
      </div>
    </div>
  );
}
