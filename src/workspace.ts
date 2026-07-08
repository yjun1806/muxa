import { type TreeNode, makePane, newId } from "./tree";

/** 워크스페이스 하나 = 경로 + 자기 분할 트리 + 포커스. */
export interface Workspace {
  id: string;
  path?: string; // 셸 cwd. 초기 워크스페이스는 프로세스 cwd라 undefined일 수 있다
  name: string; // 표시 이름(경로 basename)
  tree: TreeNode;
  focusedId: string;
}

export function basename(path: string): string {
  const parts = path.replace(/\/+$/, "").split("/");
  return parts[parts.length - 1] || path;
}

export function createWorkspace(path?: string, name?: string): Workspace {
  const pane = makePane();
  return {
    id: newId(),
    path,
    name: name ?? (path ? basename(path) : "workspace"),
    tree: pane,
    focusedId: pane.id,
  };
}
