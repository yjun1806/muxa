import type { Workspace } from "./workspace";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  collapsed: boolean;
  onSelect: (id: string) => void;
}

/**
 * 좌측 워크스페이스 사이드바 — 목록만(추가 액션은 상단바로).
 * 열림/닫힘은 두 상태로 구분: 닫히면 width 0으로 슬라이드해 완전히 사라진다(콘텐츠 풀폭).
 */
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
            <span className="ws-name">{ws.name}</span>
            <span className="ws-badge">{i < 8 ? `⌘${i + 1}` : ""}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
