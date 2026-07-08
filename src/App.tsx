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

  // 초기 워크스페이스 — 앱의 현재 디렉터리로. cwd를 먼저 알아야 셸이 옳은 위치에서 시작한다.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const dir = await invoke<string | null>("current_dir");
      if (cancelled) return;
      const ws = createWorkspace(dir ?? undefined);
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

  const addWorkspace = useCallback(async () => {
    const dir = await open({ directory: true, multiple: false });
    if (typeof dir !== "string") return;
    const ws = createWorkspace(dir);
    setWorkspaces((prev) => [...prev, ws]);
    setActiveId(ws.id);
  }, []);

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
    <div style={{ display: "flex", height: "100%", width: "100%" }}>
      <Sidebar
        workspaces={workspaces}
        activeId={activeId}
        onSelect={setActiveId}
        onAdd={addWorkspace}
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
  );
}

export default App;
