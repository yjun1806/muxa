import AppKit

/// "이 워크스페이스에 프로젝트를 하나 더" 항목들 — 사이드바 워크스페이스 행의 `+` 버튼과
/// 워크스페이스 우클릭 메뉴가 **같은 목록**을 쓴다(항목 구성은 구 ProjectTabBar의 +에서 그대로 옮겨왔다).
///
/// 우클릭 메뉴에도 실리는 이유: `+` 버튼은 확장 트리의 hover에서만 존재한다. 접힌 모드(icon·slim)에선
/// 이 목록이 **워크트리 생성의 유일한 경로**다.
///
/// 각 항목이 먼저 그 워크스페이스를 활성으로 만든다 — `AppState.addProject`와 워크트리 시트는
/// 활성 워크스페이스를 대상으로 하므로, 안 그러면 프로젝트가 엉뚱한 곳에 조용히 생긴다.
@MainActor
enum ProjectAddMenu {
    static func items(for workspace: Workspace, state: AppState) -> [MuxaMenuItem] {
        [
            MuxaMenuItem(icon: "plus.square", title: "새 프로젝트 (같은 폴더)") {
                state.setActiveId(workspace.id)
                state.addProject(name: "프로젝트 \(workspace.projects.count + 1)", path: nil)
            },
            // 시트는 뷰 계층(ContentView)이 소유하므로 여기선 요청만 올린다 —
            // 여는 버튼(hover의 +)이 사라져도 시트는 살아 있어야 한다.
            MuxaMenuItem(icon: "arrow.triangle.branch", title: "워크트리…") {
                state.setActiveId(workspace.id)
                state.worktreePickerRequested = true
            },
            MuxaMenuItem(icon: "folder", title: "임의 폴더 선택…") {
                guard let path = FolderPrompt.pick(startingAt: workspace.path) else { return }
                state.setActiveId(workspace.id)
                state.addProject(name: basename(path), path: path)
            },
        ]
    }
}
