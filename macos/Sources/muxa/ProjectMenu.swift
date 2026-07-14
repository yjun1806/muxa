import AppKit

/// 프로젝트 탭(상단바) 우클릭 메뉴. 프로젝트 = 폴더 하나에서 시작하는 독립 분할 레이아웃이라
/// 이름·경로·닫기가 핵심이다. 워크트리 생성·제거는 이미 전용 UI(WorktreePicker·Git 패널)가 담당하므로 넣지 않는다.
@MainActor
enum ProjectMenu {
    static func items(for project: Project, in workspace: Workspace, state: AppState) -> [MuxaMenuItem] {
        // 프로젝트 경로가 없으면 워크스페이스 폴더를 상속한다(Project.path == nil의 의미).
        let path = project.path ?? workspace.path

        return [
            MuxaMenuItem(icon: "pencil", title: "이름 변경…") { promptRename(project, state: state) },
            MuxaMenuItem(icon: "plus.square", title: "새 터미널", shortcut: "⌘T") {
                // 스토어 획득을 **여기 안에서** 한다 — store(for:in:)은 없으면 만든다(= PTY 기동).
                // items를 만들 때 부르면 사이드바에서 우클릭하는 것만으로 셸이 떠 버린다.
                state.setActiveId(workspace.id)    // 다른 워크스페이스의 프로젝트일 수 있다
                state.setActiveProject(project.id) // 안 보고 있는 프로젝트에 터미널만 생기면 놓친다 — 함께 전환.
                state.store(for: project, in: workspace).newTerminal()
            },
            .separator,
            MuxaMenuItem(icon: "arrow.up.forward.app", title: "Finder에서 열기", enabled: path != nil) {
                guard let path else { return }
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            },
            MuxaMenuItem(icon: "doc.on.doc", title: "경로 복사", enabled: path != nil) {
                guard let path else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
            .separator,
            MuxaMenuItem(icon: "xmark.circle", title: "프로젝트 닫기", destructive: true,
                         enabled: workspace.projects.count > 1) {
                state.closeProject(project.id)
            },
        ]
    }

    private static func promptRename(_ project: Project, state: AppState) {
        let alert = NSAlert()
        alert.messageText = "프로젝트 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = project.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.renameProject(project.id, to: field.stringValue)
    }
}
