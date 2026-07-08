import { useState } from "react";
import { createPortal } from "react-dom";
import type { Workspace } from "./workspace";
import type { SidebarMode } from "./sidebarMode";

interface Props {
  workspaces: Workspace[];
  activeId: string;
  mode: SidebarMode;
  onSelect: (id: string) => void;
}

interface Tip {
  name: string;
  x: number;
  y: number;
}

/**
 * 좌측 워크스페이스 사이드바. 표시 모드 4종:
 * - expanded: 아바타+이름  - icon: 아바타만  - slim: 얇은 위치 바
 * - hover: 평소 아이콘, 마우스 올리면 목록이 오버레이로 펼쳐짐(콘텐츠는 안 밀림).
 * icon/slim에서는 이름이 안 보이므로 호버 시 fixed 툴팁으로 이름을 띄운다.
 */
export function Sidebar({ workspaces, activeId, mode, onSelect }: Props) {
  const [peek, setPeek] = useState(false);
  const [tip, setTip] = useState<Tip | null>(null);
  const peeking = mode === "hover" && peek;
  const display: SidebarMode = peeking ? "expanded" : mode;
  const tipEnabled = mode === "icon" || mode === "slim";

  const showTip = (name: string, el: HTMLElement) => {
    if (!tipEnabled) return;
    const r = el.getBoundingClientRect();
    setTip({ name, x: r.right + 8, y: r.top + r.height / 2 });
  };

  return (
    <div
      className={`sidebar sidebar-${mode}${peeking ? " peeking" : ""}`}
      onMouseEnter={() => setPeek(true)}
      onMouseLeave={() => {
        setPeek(false);
        setTip(null);
      }}
    >
      <div className="ws-list">
        {workspaces.map((ws, i) => (
          <button
            key={ws.id}
            className={`ws-item${ws.id === activeId ? " active" : ""}`}
            title={ws.path ?? ws.name}
            onClick={() => onSelect(ws.id)}
            onMouseEnter={(e) => showTip(ws.name, e.currentTarget)}
            onMouseLeave={() => setTip(null)}
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

      {tip &&
        createPortal(
          <div className="ws-tip" style={{ left: tip.x, top: tip.y }}>
            {tip.name}
          </div>,
          document.body,
        )}
    </div>
  );
}
