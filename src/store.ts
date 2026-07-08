import { create } from "zustand";
import { persist } from "zustand/middleware";
import { type Workspace, createWorkspace } from "./workspace";
import type { SidebarMode } from "./sidebarMode";
import type { TreeNode } from "./tree";

// 앱 전역 상태 + 영속(zustand persist → localStorage).
// 재시작 시 워크스페이스 레이아웃·cwd·사이드바 모드가 복원된다.
// PTY는 프로세스라 복원 불가 → 트리 구조/cwd만 저장하고 패인은 새로 spawn.
// (D9 SQLite는 쿼리·세션 히스토리가 필요할 때 이관)

interface AppState {
  workspaces: Workspace[];
  activeId: string;
  sidebarMode: SidebarMode;

  setActiveId: (id: string) => void;
  setSidebarMode: (mode: SidebarMode) => void;
  addWorkspace: (path?: string) => void;
  updateWorkspace: (id: string, tree: TreeNode, focusedId: string) => void;
  /** 복원된 워크스페이스가 없을 때만 초기 워크스페이스를 만든다. */
  ensureInitial: (path?: string) => void;
}

export const useStore = create<AppState>()(
  persist(
    (set, get) => ({
      workspaces: [],
      activeId: "",
      sidebarMode: "expanded",

      setActiveId: (id) => set({ activeId: id }),
      setSidebarMode: (mode) => set({ sidebarMode: mode }),

      addWorkspace: (path) => {
        const ws = createWorkspace(path);
        set((s) => ({ workspaces: [...s.workspaces, ws], activeId: ws.id }));
      },

      updateWorkspace: (id, tree, focusedId) =>
        set((s) => ({
          workspaces: s.workspaces.map((w) => (w.id === id ? { ...w, tree, focusedId } : w)),
        })),

      ensureInitial: (path) => {
        if (get().workspaces.length > 0) return;
        const ws = createWorkspace(path);
        set({ workspaces: [ws], activeId: ws.id });
      },
    }),
    {
      name: "muxa.state.v1",
      // 상태만 저장(액션 제외). localStorage는 동기 복원이라 첫 렌더에 이미 복원됨.
      partialize: (s) => ({
        workspaces: s.workspaces,
        activeId: s.activeId,
        sidebarMode: s.sidebarMode,
      }),
    },
  ),
);
