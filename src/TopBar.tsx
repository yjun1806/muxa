import { Folder, FolderOpen, PanelLeftClose, PanelLeftOpen, Plus } from "lucide-react";
import { ICON, ICON_SM } from "./icons";

interface Props {
  activeName?: string;
  activePath?: string;
  collapsed: boolean;
  onToggleCollapse: () => void;
  onAdd: () => void;
  onPick: () => void;
}

/**
 * 전체 폭 상단바 — 사이드바 폭과 무관하게 고정(접어도 흔들리지 않음).
 * 신호등 자리 + 워크스페이스 액션(접기·추가·폴더) + 활성 워크스페이스 정보.
 * 빈 영역은 data-tauri-drag-region으로 창 이동(버튼·정보만 상호작용 섬).
 */
export function TopBar({
  activeName,
  activePath,
  collapsed,
  onToggleCollapse,
  onAdd,
  onPick,
}: Props) {
  return (
    <div className="topbar" data-tauri-drag-region>
      <div className="topbar-lights" data-tauri-drag-region />

      <button
        className="tool-btn"
        title={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        aria-label={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
        onClick={onToggleCollapse}
      >
        {collapsed ? <PanelLeftOpen {...ICON} /> : <PanelLeftClose {...ICON} />}
      </button>
      <button
        className="tool-btn"
        title="새 워크스페이스 (홈)"
        aria-label="새 워크스페이스"
        onClick={onAdd}
      >
        <Plus {...ICON} />
      </button>
      <button
        className="tool-btn"
        title="폴더 선택해 워크스페이스"
        aria-label="폴더 선택"
        onClick={onPick}
      >
        <FolderOpen {...ICON} />
      </button>

      <div className="topbar-ws" data-tauri-drag-region>
        <Folder {...ICON_SM} />
        <span className="topbar-ws-name">{activeName ?? ""}</span>
        {activePath && <span className="topbar-ws-path">{activePath}</span>}
      </div>

      <div className="topbar-spacer" data-tauri-drag-region />
    </div>
  );
}
