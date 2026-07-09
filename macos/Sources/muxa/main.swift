import AppKit
import Bonsplit
import Carbon.HIToolbox
import GhosttyKit
import SwiftUI

// muxa — SwiftUI 크롬 + AppKit(GhosttyKit) 터미널 하이브리드 (DESIGN.md D16).
// AppKit이 NSWindow·activation을 제어(raw 실행에도 창이 확실히 뜬다)하고,
// NSHostingView로 SwiftUI UI를 그 안에 임베드한다. Ghostty와 같은 구조.

guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
    fatalError("ghostty_init failed")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime?
    private var state: AppState?
    private var window: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime = GhosttyRuntime(), let app = runtime.app else {
            fatalError("GhosttyRuntime init failed")
        }
        self.runtime = runtime

        // 저장된 세션 복원(없으면 현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState(app: app)
        state.load()
        state.ensureInitial(path: SystemPaths.currentDir ?? SystemPaths.home)
        self.state = state

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "muxa"
        // 타이틀바를 투명·제목숨김으로 만들어 신호등만 남기고, 상단바 컨트롤은 액세서리로 그 줄에 얹는다(Tauri식)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true // 빈 영역 드래그로 창 이동(Tauri drag-region 대체)
        window.backgroundColor = Palette.panel // 타이틀바(=창 배경)를 상단바와 같은 회색으로
        window.center()

        // 크롬(사이드바) + 활성 워크스페이스(Bonsplit 탭바·분할)를 SwiftUI로 렌더.
        window.contentView = NSHostingView(rootView: ContentView(state: state, home: SystemPaths.home))

        // 상단바 컨트롤을 타이틀바 신호등 오른쪽(.leading)에 얹는다 — SwiftUI 콘텐츠에 넣으면 가려진다.
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .leading
        let controls = NSHostingView(rootView: TopBarControls(state: state, home: SystemPaths.home))
        controls.sizingOptions = [.intrinsicContentSize]
        accessory.view = controls
        window.addTitlebarAccessoryViewController(accessory)

        window.makeKeyAndOrderFront(nil)
        self.window = window

        // 단축키 — 포커스된 터미널이 키를 먼저 먹으므로 로컬 모니터로 가로챈다.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                self.handleShortcut(event) ? nil : event
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌘1-8 워크스페이스 · ⌘T 새 터미널 · ⌘D/⌘⇧D 분할 · ⌘W 탭 닫기.
    /// 물리 keyCode로 판별한다 — charactersIgnoringModifiers는 한글 자판에서 어긋난다.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.window === window, event.modifierFlags.contains(.command),
              let state else { return false }
        let shift = event.modifierFlags.contains(.shift)

        // ⌘1-8: 워크스페이스 전환 (숫자는 자판 무관하게 charactersIgnoringModifiers로)
        if let s = event.charactersIgnoringModifiers, let n = Int(s),
           n >= 1, n <= 8, state.workspaces.indices.contains(n - 1) {
            state.setActiveId(state.workspaces[n - 1].id)
            return true
        }

        guard let ws = state.activeWorkspace else { return false }
        let controller = state.store(for: ws).controller

        switch Int(event.keyCode) {
        case kVK_ANSI_T:
            _ = state.store(for: ws).newTerminal(inPane: controller.focusedPaneId)
            return true
        case kVK_ANSI_D:
            _ = controller.splitPane(orientation: shift ? .vertical : .horizontal)
            return true
        case kVK_ANSI_W:
            if let pane = controller.focusedPaneId, let tab = controller.selectedTab(inPane: pane) {
                _ = controller.closeTab(tab.id, inPane: pane)
            }
            return true
        default:
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// AppDelegate가 @MainActor라 top-level(nonisolated)에서 직접 못 만든다 — 메인 스레드 실행이 보장되므로 assumeIsolated.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate // delegate는 weak지만 run()이 블록되는 동안 이 스코프가 유지한다
    app.run()
}
