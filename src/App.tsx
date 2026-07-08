import { useCallback, useEffect, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { invoke } from "@tauri-apps/api/core";
import { WorkspaceView } from "./WorkspaceView";
import { Sidebar } from "./Sidebar";
import { TopBar } from "./TopBar";
import { displayPath } from "./workspace";
import { useStore } from "./store";

function App() {
  const workspaces = useStore((s) => s.workspaces);
  const activeId = useStore((s) => s.activeId);
  const sidebarMode = useStore((s) => s.sidebarMode);
  const setActiveId = useStore((s) => s.setActiveId);
  const setSidebarMode = useStore((s) => s.setSidebarMode);
  const addWorkspace = useStore((s) => s.addWorkspace);
  const updateWorkspace = useStore((s) => s.updateWorkspace);

  const [home, setHome] = useState<string | undefined>(undefined);

  // 홈 경로 조회 + (복원된 게 없으면) 초기 워크스페이스 생성.
  // persist는 localStorage 동기 복원이라 이 시점엔 이미 저장분이 로드돼 있다.
  // store는 getState()로 비반응형 접근 → 마운트 1회 실행([] deps).
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const hd = await invoke<string | null>("home_dir");
      if (cancelled) return;
      setHome(hd ?? undefined);
      if (useStore.getState().workspaces.length === 0) {
        const dir = await invoke<string | null>("current_dir");
        if (cancelled) return;
        useStore.getState().ensureInitial(dir ?? hd ?? undefined);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // "+" — 홈에 즉시 새 워크스페이스
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
  }, [workspaces, setActiveId]);

  const active = workspaces.find((w) => w.id === activeId);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", width: "100%" }}>
      <TopBar
        activeName={active?.name}
        activePath={displayPath(active?.path, home)}
        mode={sidebarMode}
        onSetMode={setSidebarMode}
        onAddHome={addAtHome}
        onPick={addByPick}
      />
      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        <Sidebar
          workspaces={workspaces}
          activeId={activeId}
          mode={sidebarMode}
          onSelect={setActiveId}
        />
        <div className="content-body">
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
