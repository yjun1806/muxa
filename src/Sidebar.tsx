import { Plus, FolderOpen } from "lucide-react";
import type { Workspace } from "./workspace";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  onSelect: (id: string) => void;
  onAdd: () => void; // 홈에 즉시 추가
  onPick: () => void; // 폴더 선택해 추가
}

/** 좌측 워크스페이스 사이드바 — 수직 나열 + ⌘1-8 힌트 + 추가. */
export function Sidebar({ workspaces, activeId, onSelect, onAdd, onPick }: Props) {
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
      <div className="ws-actions">
        <button
          className="ws-add"
          title="새 워크스페이스 (홈)"
          aria-label="새 워크스페이스"
          onClick={onAdd}
        >
          <Plus size={16} strokeWidth={1.5} />
        </button>
        <button
          className="ws-add"
          title="폴더 선택해 워크스페이스"
          aria-label="폴더 선택"
          onClick={onPick}
        >
          <FolderOpen size={16} strokeWidth={1.5} />
        </button>
      </div>
    </div>
  );
}
