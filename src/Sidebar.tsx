import { useState } from "react";
import type { Workspace } from "./workspace";
import type { SidebarMode } from "./sidebarMode";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  mode: SidebarMode;
  onSelect: (id: string) => void;
}

/**
 * 좌측 워크스페이스 사이드바. 표시 모드 4종:
 * - expanded: 아바타+이름  - icon: 아바타만  - slim: 얇은 위치 바
 * - hover: 평소 아이콘, 마우스 올리면 목록이 오버레이로 펼쳐짐(콘텐츠는 안 밀림).
 */
export function Sidebar({ workspaces, activeId, mode, onSelect }: Props) {
  const [peek, setPeek] = useState(false);
  const peeking = mode === "hover" && peek;
  // 실제 렌더 형태 — 호버 펼침 중이면 expanded처럼 그린다
  const display: SidebarMode = peeking ? "expanded" : mode;

  return (
    <div
      className={`sidebar sidebar-${mode}${peeking ? " peeking" : ""}`}
      onMouseEnter={() => setPeek(true)}
      onMouseLeave={() => setPeek(false)}
    >
      <div className="ws-list">
        {workspaces.map((ws, i) => (
          <button
            key={ws.id}
            className={`ws-item${ws.id === activeId ? " active" : ""}`}
            title={ws.path ?? ws.name}
            onClick={() => onSelect(ws.id)}
          >
            {display === "slim" ? (
              <span className="ws-bar" />
            ) : (
              <span className="ws-avatar">{ws.name.charAt(0).toUpperCase()}</span>
            )}
            {display === "expanded" && <span className="ws-name">{ws.name}</span>}
            {display === "expanded" && <span className="ws-badge">{i < 8 ? `⌘${i + 1}` : ""}</span>}
          </button>
        ))}
      </div>
    </div>
  );
}
