import type { Workspace } from "./workspace";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  collapsed: boolean;
  onSelect: (id: string) => void;
}

/** 좌측 워크스페이스 사이드바 — 목록만(추가 액션은 상단바로). 접힘 상태는 아바타만. */
export function Sidebar({ workspaces, activeId, collapsed, onSelect }: Props) {
  return (
    <div className={`sidebar${collapsed ? " collapsed" : ""}`}>
      <div className="ws-list">
        {workspaces.map((ws, i) => (
          <button
            key={ws.id}
            className={`ws-item${ws.id === activeId ? " active" : ""}`}
            title={ws.path ?? ws.name}
            onClick={() => onSelect(ws.id)}
          >
            <span className="ws-avatar">{ws.name.charAt(0).toUpperCase()}</span>
            {!collapsed && <span className="ws-name">{ws.name}</span>}
            {!collapsed && <span className="ws-badge">{i < 8 ? `⌘${i + 1}` : ""}</span>}
          </button>
        ))}
      </div>
    </div>
  );
}
