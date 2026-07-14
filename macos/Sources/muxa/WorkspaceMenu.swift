import AppKit

/// 워크스페이스 우클릭 메뉴 — 항목 구성과 그 항목이 여는 입력 다이얼로그를 한곳에 모은다.
/// 상태 변경은 전부 `AppState`(단일 소유자)에 위임하고, 여기선 "무엇을 물어보고 무엇을 부르는지"만 정한다.
/// 띄우기는 `MuxaMenuWindow`가 담당한다.
@MainActor
enum WorkspaceMenu {
    /// 사이드바 워크스페이스 항목의 메뉴. `canRemove`가 false면(마지막 하나) 닫기 항목이 비활성으로 남는다.
    ///
    /// **프로젝트 추가 항목(`ProjectAddMenu`)을 함께 싣는다** — 확장 트리의 `+` 버튼은 hover에서만
    /// 존재하고 접힌 모드(icon·slim)엔 아예 없다. 여기에 없으면 그 모드에서 워크트리를 만들 방법이 없다.
    static func items(for workspace: Workspace, state: AppState) -> [MuxaMenuItem] {
        let path = workspace.path
        return [
            MuxaMenuItem(icon: "pencil", title: "이름 변경…") { promptRename(workspace, state: state) },
            MuxaMenuItem(icon: "folder.badge.gearshape", title: "기본 경로 변경…") { promptPath(workspace, state: state) },
            MuxaMenuItem(icon: "plus.square.on.square", title: "워크스페이스 복제") { state.duplicateWorkspace(workspace.id) },
            // 워크스페이스 분리 = 그 안의 전 프로젝트를 새 창으로 옮기는 것(move의 설탕 — D29).
            // 이미 전부 분리돼 있으면 옮길 게 없다.
            MuxaMenuItem(icon: "macwindow", title: "새 창으로 분리",
                         enabled: workspace.projects.contains { state.owner(of: $0.id).isMain }) {
                state.separateWorkspace(workspace.id)
            },
            .separator,
        ] + ProjectAddMenu.items(for: workspace, state: state) + [
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
            MuxaMenuItem(icon: "xmark.circle", title: "워크스페이스 닫기", destructive: true,
                         enabled: state.workspaces.count > 1) {
                promptRemove(workspace, state: state)
            },
        ]
    }

    // MARK: 입력 다이얼로그 (기존 탭 이름 변경·discard 확인과 같은 NSAlert 패턴)

    private static func promptRename(_ workspace: Workspace, state: AppState) {
        let alert = NSAlert()
        alert.messageText = "워크스페이스 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = workspace.name
        field.placeholderString = workspace.path.map(basename) ?? "workspace"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.renameWorkspace(workspace.id, to: field.stringValue)
    }

    /// 기본 경로 변경 — 폴더 선택. 이미 떠 있는 터미널의 cwd는 못 바꾸므로 그 사실을 패널에 미리 알린다.
    private static func promptPath(_ workspace: Workspace, state: AppState) {
        let path = FolderPrompt.pick(
            startingAt: workspace.path,
            prompt: "이 폴더로 변경",
            message: "파일 익스플로러·Git 패널과 앞으로 여는 터미널에 적용됩니다. "
                + "이미 열려 있는 터미널은 기존 폴더에 그대로 남습니다.")
        guard let path else { return }
        state.setWorkspacePath(workspace.id, path: path)
    }

    private static func promptRemove(_ workspace: Workspace, state: AppState) {
        let alert = NSAlert()
        alert.messageText = "'\(workspace.name)' 워크스페이스를 닫을까요?"
        alert.informativeText = "이 워크스페이스의 프로젝트·탭 구성과 저장된 레이아웃이 사라집니다. "
            + "폴더의 파일은 지워지지 않습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.removeWorkspace(workspace.id)
    }
}
