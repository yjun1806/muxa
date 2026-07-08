import { Plus } from "lucide-react";
import type { Workspace } from "./workspace";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  onSelect: (id: string) => void;
  onAdd: () => void;
}

/** 좌측 워크스페이스 사이드바 — 수직 나열 + ⌘1-8 힌트 + 추가. */
export function Sidebar({ workspaces, activeId, onSelect, onAdd }: Props) {
  return (
    <div className="sidebar">
      <div className="ws-list">
        {workspaces.map((ws, i) => (
          <button
            key={ws.id}
            className={`ws-item${ws.id === activeId ? " active" : ""}`}
            title={ws.path ?? ws.name}
            onClick={() => onSelect(ws.id)}
          >
            <span className="ws-badge">{i < 8 ? `⌘${i + 1}` : ""}</span>
            <span className="ws-name">{ws.name}</span>
          </button>
        ))}
      </div>
      <button
        className="ws-add"
        title="워크스페이스 추가"
        aria-label="워크스페이스 추가"
        onClick={onAdd}
      >
        <Plus size={16} strokeWidth={1.5} />
      </button>
    </div>
  );
}
