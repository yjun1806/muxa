import { Folder, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { ICON, ICON_SM } from "./icons";

interface Props {
  activeName?: string;
  collapsed: boolean;
  onToggleCollapse: () => void;
}

/**
 * 상단바 — 신호등 자리 + 사이드바 토글 + 활성 워크스페이스 제목.
 * 빈 영역은 data-tauri-drag-region으로 창 이동 가능(버튼만 상호작용 섬).
 */
export function TopBar({ activeName, collapsed, onToggleCollapse }: Props) {
  return (
    <div className="titlebar" data-tauri-drag-region>
      <div className="titlebar-lights" data-tauri-drag-region />
      <button
        className="tool-btn"
        title={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        aria-label={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        onClick={onToggleCollapse}
      >
        {collapsed ? <PanelLeftOpen {...ICON} /> : <PanelLeftClose {...ICON} />}
      </button>
      <div className="titlebar-title" data-tauri-drag-region>
        <Folder {...ICON_SM} />
        <span>{activeName ?? ""}</span>
      </div>
    </div>
  );
}
