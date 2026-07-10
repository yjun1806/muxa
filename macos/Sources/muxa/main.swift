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
    /// 단축키 판정 테이블 — 설정 로드 후 재정의를 얹어 교체한다(그전까진 기본 테이블).
    private var keymap = KeymapResolver.default

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime = GhosttyRuntime(), let app = runtime.app else {
            fatalError("GhosttyRuntime init failed")
        }
        self.runtime = runtime

        ShikiHighlighter.shared.warmUp() // 코드 하이라이터를 미리 로드 — 첫 코드 파일도 즉시 뜨게
        NotificationService.shared.requestAuthorizationIfPossible() // 데스크톱 알림 권한(번들일 때만)
        setupMainMenu() // ⌘Q(종료)·⌘H(가리기) — 메뉴가 없으면 ⌘Q가 안 묶인다

        // muxa 설정(~/.config/muxa/config) 로드 — 없으면 전부 기본값. 폰트·테마는 ghostty config 재사용(GhosttyRuntime). (DESIGN 4.6)
        let config = MuxaConfigLoader.load()
        // 단축키 테이블 — 설정의 keybinding 재정의를 기본 위에 얹는다(없으면 기본 그대로). (DESIGN 7)
        keymap = KeymapResolver(overrides: config.keybindings)

        // 저장된 세션 복원(없으면 설정의 기본 경로/현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState(app: app, config: config)
        state.load()
        state.ensureInitial(path: config.defaultWorkspacePath ?? SystemPaths.currentDir ?? SystemPaths.home)
        state.startNotifyServer() // 훅 알림 소켓 리스너 시작 — `muxa notify`가 결정론적 신호를 보낸다
        // 시스템 알림 클릭 → 프로젝트 활성 + Git 패널(원클릭 검토 동선). 라우팅 소유는 AppState.
        NotificationService.shared.onActivate = { [weak state] ctx in
            state?.revealActivity(projectId: ctx.projectId, tabId: ctx.tabId)
        }
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

    /// 로컬 키 모니터의 착지점 — 판정은 KeymapResolver(순수)에 위임하고, 매치되면 실행 후 소비(true),
    /// 미매치면 통과(false → 포커스된 터미널이 먹는다). 우리 창 이벤트만 대상. (DESIGN 7 라우팅 규칙)
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.window === window, let state else { return false }
        guard let action = keymap.resolve(keyCode: Int(event.keyCode),
                                          characters: event.charactersIgnoringModifiers,
                                          flags: event.modifierFlags) else { return false }
        return perform(action, state: state)
    }

    /// 크롬 동작 실행 — 성공(소비)이면 true. 활성 스토어가 필요한 동작은 없으면 통과(false).
    private func perform(_ action: KeymapAction, state: AppState) -> Bool {
        switch action {
        case .switchWorkspace(let n):
            guard state.workspaces.indices.contains(n - 1) else { return false }
            state.setActiveId(state.workspaces[n - 1].id)
            return true
        case .cycleProject(let forward):
            state.cycleProject(forward: forward); return true
        case .toggleExplorer:
            state.toggleExplorer(); return true
        case .toggleGitPanel:
            state.toggleGitPanel(); return true
        case .jumpToNextWaiting:
            state.jumpToNextWaiting(); return true
        case .newTerminal, .split, .closeTab, .find, .focusPane, .cycleTab:
            guard let store = state.activeStore else { return false }
            return perform(action, store: store)
        }
    }

    /// 활성 스토어(분할·탭 컨트롤러)를 대상으로 하는 동작 실행.
    private func perform(_ action: KeymapAction, store: TerminalStore) -> Bool {
        let controller = store.controller
        switch action {
        case .newTerminal:
            _ = store.newTerminal(inPane: controller.focusedPaneId)
        case .split(let vertical):
            _ = controller.splitPane(orientation: vertical ? .vertical : .horizontal)
        case .closeTab:
            if let pane = controller.focusedPaneId, let tab = controller.selectedTab(inPane: pane) {
                _ = controller.closeTab(tab.id, inPane: pane)
            }
        case .find:
            store.focusedTerm?.startSearch()
        case .focusPane(let direction):
            controller.navigateFocus(direction: direction)
        case .cycleTab(let forward):
            forward ? controller.selectNextTab() : controller.selectPreviousTab()
        default:
            return false // 스토어 비대상 동작은 상위 perform이 이미 처리 — 방어적 폴백.
        }
        return true
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

    /// 종료 확인 — 실행 중인 터미널 세션이 다 닫히므로 실수 종료를 막는다. 설정 confirm_quit=false면 건너뛴다. (DESIGN 4.6)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state?.config.confirmQuit ?? true else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "muxa를 종료할까요?"
        alert.informativeText = "실행 중인 터미널 세션이 모두 종료됩니다."
        alert.addButton(withTitle: "종료") // 첫 버튼 = 기본(Enter)
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

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
