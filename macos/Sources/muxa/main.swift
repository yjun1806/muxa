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

        setupMainMenu() // ⌘Q(종료)·⌘H(가리기) — 메뉴가 없으면 ⌘Q가 안 묶인다

        // 저장된 세션 복원(없으면 현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState(app: app)
        state.load()
        state.ensureInitial(path: SystemPaths.currentDir ?? SystemPaths.home)
        self.state = state

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "muxa"
        // 콘텐츠를 타이틀바까지 끌어올리고(fullSizeContentView) 신호등만 남긴다. 상단바 컨트롤은
        // SwiftUI 본문 최상단에 직접 둔다 — 타이틀바 액세서리는 렌더가 불안정해 비어 보였다.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true // 빈 영역 드래그로 창 이동(Tauri drag-region 대체)
        window.backgroundColor = Palette.panel // 창 배경을 상단바와 같은 회색으로
        window.center()

        // 크롬(상단바·사이드바) + 활성 워크스페이스(Bonsplit 탭바·분할)를 SwiftUI로 렌더.
        let hosting = NSHostingView(rootView: ContentView(state: state, home: SystemPaths.home))
        // safe-area를 끈다 — 안 그러면 SwiftUI가 타이틀바 아래로 콘텐츠를 밀어 상단바가
        // 신호등과 다른 줄로 분리된다(두 줄). 꺼야 콘텐츠가 타이틀바 밑까지 올라와 한 줄이 된다.
        hosting.safeAreaRegions = []
        window.contentView = hosting

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

        // ⌘⇧[ / ⌘⇧] : 프로젝트 전환(브라우저 탭 관례)
        if shift, Int(event.keyCode) == kVK_ANSI_LeftBracket {
            state.cycleProject(forward: false)
            return true
        }
        if shift, Int(event.keyCode) == kVK_ANSI_RightBracket {
            state.cycleProject(forward: true)
            return true
        }

        guard let store = state.activeStore else { return false }
        let controller = store.controller

        switch Int(event.keyCode) {
        case kVK_ANSI_T:
            _ = store.newTerminal(inPane: controller.focusedPaneId)
            return true
        case kVK_ANSI_D:
            _ = controller.splitPane(orientation: shift ? .vertical : .horizontal)
            return true
        case kVK_ANSI_W:
            if let pane = controller.focusedPaneId, let tab = controller.selectedTab(inPane: pane) {
                _ = controller.closeTab(tab.id, inPane: pane)
            }
            return true
        case kVK_ANSI_F:
            store.focusedTerm?.startSearch()
            return true
        default:
            return false
        }
    }

    /// 최소 메인 메뉴 — App 메뉴에 종료(⌘Q)·가리기(⌘H)만. Edit 메뉴의 ⌘C/⌘V는 터미널
    /// 복사·붙여넣기(ghostty가 직접 처리)를 가로채므로 넣지 않는다.
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "muxa 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "muxa 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 종료 직전 현재 분할 레이아웃을 저장한다 — split/탭 변경은 자체 save를 안 부르므로 여기서 확정.
    func applicationWillTerminate(_ notification: Notification) {
        state?.save()
    }
}

// AppDelegate가 @MainActor라 top-level(nonisolated)에서 직접 못 만든다 — 메인 스레드 실행이 보장되므로 assumeIsolated.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate // delegate는 weak지만 run()이 블록되는 동안 이 스코프가 유지한다
    app.run()
}
