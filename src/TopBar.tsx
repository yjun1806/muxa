import { Folder } from "lucide-react";
import { ICON_SM } from "./icons";
import { SidebarControls } from "./SidebarControls";
import type { SidebarMode } from "./sidebarMode";

interface Props {
  activeName?: string;
  activePath?: string;
  mode: SidebarMode;
  onSetMode: (mode: SidebarMode) => void;
  onAddHome: () => void;
  onPick: () => void;
}

/**
 * 전체 폭 상단바. 사이드바와 같은 회색이라 세로로 이어져 "한 덩어리"처럼 보이고,
 * 콘텐츠(흰색)와는 색 대비로 갈린다. 사이드바 폭에 묶이지 않아 접어도 흔들리지 않음.
 * 빈 영역은 창 이동 드래그(버튼·정보만 상호작용 섬).
 */
export function TopBar({ activeName, activePath, mode, onSetMode, onAddHome, onPick }: Props) {
  return (
    <div className="topbar" data-tauri-drag-region>
      <div className="topbar-lights" data-tauri-drag-region />
      <SidebarControls mode={mode} onSetMode={onSetMode} onAddHome={onAddHome} onPick={onPick} />
      <div className="topbar-ws" data-tauri-drag-region>
        <Folder {...ICON_SM} />
        <span className="topbar-ws-name">{activeName ?? ""}</span>
        {activePath && <span className="topbar-ws-path">{activePath}</span>}
      </div>
      <div className="topbar-spacer" data-tauri-drag-region />
    </div>
  );
}
