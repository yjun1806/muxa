import { Folder, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { ICON, ICON_SM } from "./icons";

interface Props {
  activeName?: string;
  collapsed: boolean;
  onToggleCollapse: () => void;
}

/**
 * 콘텐츠 컬럼 상단바 — 사이드바 토글 + 활성 워크스페이스 제목.
 * 사이드바 상단바(신호등 자리)와 같은 높이로, 창 상단을 2분할한다. 빈 영역은 드래그.
 */
export function ContentHeader({ activeName, collapsed, onToggleCollapse }: Props) {
  return (
    <div className="content-top" data-tauri-drag-region>
      <button
        className="tool-btn"
        title={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        aria-label={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        onClick={onToggleCollapse}
      >
        {collapsed ? <PanelLeftOpen {...ICON} /> : <PanelLeftClose {...ICON} />}
      </button>
      <div className="content-title" data-tauri-drag-region>
        <Folder {...ICON_SM} />
        <span>{activeName ?? ""}</span>
      </div>
    </div>
  );
}
