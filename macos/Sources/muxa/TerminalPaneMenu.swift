import AppKit
import Bonsplit

/// 터미널 칸 우클릭 메뉴. **터미널이 마우스를 캡처하지 않았을 때만** 뜬다 —
/// vim·tmux처럼 마우스 리포팅을 켠 앱이 돌고 있으면 우클릭은 그 앱의 것이고 이 메뉴는 나오지 않는다
/// (판정은 `TermView.mouseCaptured` = 코어에 직접 질의).
///
/// 터미널 조작(복사·붙여넣기·화면 지우기)은 ghostty 바인딩 액션에, 분할·탭은 Bonsplit(store)에 위임한다.
@MainActor
enum TerminalPaneMenu {
    static func items(store: TerminalStore, tabId: TabID, paneId: PaneID) -> [MuxaMenuItem] {
        let term = store.term(for: tabId)
        let pwd = term.pwd

        return [
            // 선택이 없으면 코어가 알아서 무시한다.
            MuxaMenuItem(icon: "doc.on.doc", title: "복사", shortcut: "⌘C") {
                term.performBindingAction("copy_to_clipboard")
            },
            MuxaMenuItem(icon: "clipboard", title: "붙여넣기", shortcut: "⌘V") {
                term.performBindingAction("paste_from_clipboard")
            },
            .separator,
            MuxaMenuItem(icon: "rectangle.split.2x1", title: "오른쪽으로 분할", shortcut: "⌘D") {
                store.controller.splitPane(orientation: .horizontal)
            },
            MuxaMenuItem(icon: "rectangle.split.1x2", title: "아래로 분할", shortcut: "⌘⇧D") {
                store.controller.splitPane(orientation: .vertical)
            },
            MuxaMenuItem(icon: "plus.square", title: "새 터미널 탭", shortcut: "⌘T") {
                store.newTerminal(inPane: paneId)
            },
            .separator,
            MuxaMenuItem(icon: "pencil", title: "탭 이름 변경…") {
                store.promptRenameTab(tabId)
            },
            MuxaMenuItem(icon: "folder", title: "현재 경로 복사", enabled: pwd != nil) {
                guard let pwd else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pwd, forType: .string)
            },
            MuxaMenuItem(icon: "arrow.up.forward.app", title: "Finder에서 열기", enabled: pwd != nil) {
                guard let pwd else { return }
                NSWorkspace.shared.open(URL(fileURLWithPath: pwd))
            },
            .separator,
            MuxaMenuItem(icon: "eraser", title: "화면 지우기") {
                term.performBindingAction("clear_screen")
            },
            MuxaMenuItem(icon: "xmark", title: "탭 닫기", shortcut: "⌘W", destructive: true) {
                _ = store.controller.closeTab(tabId, inPane: paneId)
            },
        ]
    }
}
