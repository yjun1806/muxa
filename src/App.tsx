import { useCallback, useEffect, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { invoke } from "@tauri-apps/api/core";
import { WorkspaceView } from "./WorkspaceView";
import { Sidebar } from "./Sidebar";
import { type Workspace, createWorkspace } from "./workspace";
import type { TreeNode } from "./tree";

function App() {
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [activeId, setActiveId] = useState<string>("");
  const [home, setHome] = useState<string | undefined>(undefined);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  // 초기 워크스페이스 — 앱의 현재 디렉터리로. cwd를 먼저 알아야 셸이 옳은 위치에서 시작한다.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const [dir, hd] = await Promise.all([
        invoke<string | null>("current_dir"),
        invoke<string | null>("home_dir"),
      ]);
      if (cancelled) return;
      setHome(hd ?? undefined);
      const ws = createWorkspace(dir ?? hd ?? undefined);
      setWorkspaces([ws]);
      setActiveId(ws.id);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const updateWorkspace = useCallback((id: string, tree: TreeNode, focusedId: string) => {
    setWorkspaces((prev) => prev.map((w) => (w.id === id ? { ...w, tree, focusedId } : w)));
  }, []);

  const addWorkspace = useCallback((path?: string) => {
    const ws = createWorkspace(path);
    setWorkspaces((prev) => [...prev, ws]);
    setActiveId(ws.id);
  }, []);

  // "+" — 다이얼로그 없이 홈(루트)에 즉시 새 워크스페이스
  const addAtHome = useCallback(() => addWorkspace(home), [addWorkspace, home]);

  // 폴더 선택 — 피커는 홈에서 시작
  const addByPick = useCallback(async () => {
    const dir = await open({ directory: true, multiple: false, defaultPath: home });
    if (typeof dir === "string") addWorkspace(dir);
  }, [addWorkspace, home]);

  // ⌘1-8 워크스페이스 전환
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      const n = Number(e.key);
      if (n >= 1 && n <= 8 && workspaces[n - 1]) {
        e.preventDefault();
        e.stopPropagation();
        setActiveId(workspaces[n - 1].id);
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [workspaces]);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", width: "100%" }}>
      {/* 상단 드래그 바 — 신호등(traffic lights) 자리 확보 + 창 이동 */}
      <div className="titlebar" data-tauri-drag-region />
      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        <Sidebar
          workspaces={workspaces}
          activeId={activeId}
          collapsed={sidebarCollapsed}
          onToggleCollapse={() => setSidebarCollapsed((v) => !v)}
          onSelect={setActiveId}
          onAdd={addAtHome}
          onPick={addByPick}
        />
        <div style={{ flex: 1, minWidth: 0, position: "relative" }}>
          {workspaces.map((ws) => (
            <WorkspaceView
              key={ws.id}
              tree={ws.tree}
              focusedId={ws.focusedId}
              active={ws.id === activeId}
              cwd={ws.path}
              onChange={(tree, focusedId) => updateWorkspace(ws.id, tree, focusedId)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
