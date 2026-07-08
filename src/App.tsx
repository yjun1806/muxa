import { useState } from "react";
import { WorkspaceView } from "./WorkspaceView";
import { type TreeNode, makePane, firstPaneId } from "./tree";

// 4a: 단일 워크스페이스. 4b에서 App이 workspaces[]를 소유하고 사이드바로 전환한다.
function App() {
  const [tree, setTree] = useState<TreeNode>(() => makePane());
  const [focusedId, setFocusedId] = useState<string>(() => firstPaneId(tree));

  return (
    <WorkspaceView
      tree={tree}
      focusedId={focusedId}
      active
      onChange={(t, f) => {
        setTree(t);
        setFocusedId(f);
      }}
    />
  );
}

export default App;
