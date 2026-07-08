import { Plus, FolderOpen, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import type { Workspace } from "./workspace";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  collapsed: boolean;
  onToggleCollapse: () => void;
  onSelect: (id: string) => void;
  onAdd: () => void; // 홈에 즉시 추가
  onPick: () => void; // 폴더 선택해 추가
}

/** 좌측 워크스페이스 사이드바 — 접기/펼치기, 수직 나열, ⌘1-8 힌트, 추가. */
export function Sidebar({
  workspaces,
  activeId,
  collapsed,
  onToggleCollapse,
  onSelect,
  onAdd,
  onPick,
}: Props) {
  return (
    <div className={`sidebar${collapsed ? " collapsed" : ""}`}>
      <div className="sidebar-head">
        <button
          className="tool-btn"
          title={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
          aria-label={collapsed ? "사이드바 펼치기" : "사이드바 접기"}
          onClick={onToggleCollapse}
        >
          {collapsed ? (
            <PanelLeftOpen size={16} strokeWidth={1.5} />
          ) : (
            <PanelLeftClose size={16} strokeWidth={1.5} />
          )}
        </button>
      </div>

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

      <div className="ws-actions">
        <button
          className="ws-add"
          title="새 워크스페이스 (홈)"
          aria-label="새 워크스페이스"
          onClick={onAdd}
        >
          <Plus size={16} strokeWidth={1.5} />
        </button>
        {!collapsed && (
          <button
            className="ws-add"
            title="폴더 선택해 워크스페이스"
            aria-label="폴더 선택"
            onClick={onPick}
          >
            <FolderOpen size={16} strokeWidth={1.5} />
          </button>
        )}
      </div>
    </div>
  );
}
