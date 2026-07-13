import AppKit
import Bonsplit
import Carbon.HIToolbox
import GhosttyKit
import os
import SwiftUI

/// 키바인딩 재정의 경고 로그 채널. 사용자가 표면(콘솔·Console.app)에서 "왜 안 먹지"를 추적할 수 있게 한다.
private let keymapLog = Logger(subsystem: "com.muxa.app", category: "keybind")

// muxa — SwiftUI 크롬 + AppKit(GhosttyKit) 터미널 하이브리드 (DESIGN.md D16).
// AppKit이 NSWindow·activation을 제어(raw 실행에도 창이 확실히 뜬다)하고,
// NSHostingView로 SwiftUI UI를 그 안에 임베드한다. Ghostty와 같은 구조.

guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
    fatalError("ghostty_init failed")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var runtime: GhosttyRuntime?
    private var state: AppState?
    private var window: NSWindow?
    private var keyMonitor: Any?
    /// 휠 마우스 → 가로 전용 스크롤 영역(탭바·서브탭 바) 브리지. 앱 수명 동안 유지.
    private var wheelMonitor: Any?
    /// 단축키 판정 테이블 — 설정 로드 후 재정의를 얹어 교체한다(그전까진 기본 테이블). 라이브 리로드로 다시 교체된다.
    private var keymap = KeymapResolver.default
    /// 설정 파일 감시자 — 저장 시 자동 재적용(재시작 불필요). 부작용은 이 경계 타입에 격리. (DESIGN 4.6)
    private var configWatcher: ConfigWatcher?
    /// 시스템 외관(라이트↔다크) 감시 — 바뀌면 터미널 팔레트를 다시 굽는다(GhosttyRuntime.applyAppearance).
    private var appearanceObserver: NSKeyValueObservation?
    /// ⌘Q 시트에서 이미 "종료"를 확인받았는지 — applicationShouldTerminate가 다시 묻지 않게 한다.
    private var quitConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime = GhosttyRuntime(), let app = runtime.app else {
            fatalError("GhosttyRuntime init failed")
        }
        self.runtime = runtime

        setAppIcon() // Dock 아이콘 — bare 실행(.app 번들 아님)이라 런타임에 직접 설정
        ShikiHighlighter.shared.warmUp() // 코드 하이라이터를 미리 로드 — 첫 코드 파일도 즉시 뜨게
        NotificationService.shared.requestAuthorizationIfPossible() // 데스크톱 알림 권한(번들일 때만)
        setupMainMenu() // ⌘Q(종료)·⌘H(가리기) — 메뉴가 없으면 ⌘Q가 안 묶인다

        // muxa 설정(~/.config/muxa/config) 로드 — 없으면 전부 기본값. 폰트·테마는 ghostty config 재사용(GhosttyRuntime). (DESIGN 4.6)
        let config = MuxaConfigLoader.load()

        // 저장된 세션 복원(없으면 설정의 기본 경로/현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState(app: app, config: config)
        state.load()
        state.beginSession() // 크래시 마커 arm + 직전 더티 종료 여부 판정(노출용)
        state.ensureInitial(path: config.defaultWorkspacePath ?? SystemPaths.currentDir ?? SystemPaths.home)
        state.startNotifyServer() // 훅 알림 소켓 리스너 시작 — `muxa notify`가 결정론적 신호를 보낸다
        // 시스템 알림 클릭 → 프로젝트 활성 + Git 패널(원클릭 검토 동선). 라우팅 소유는 AppState.
        NotificationService.shared.onActivate = { [weak state] ctx in
            state?.revealActivity(projectId: ctx.projectId, tabId: ctx.tabId)
        }
        self.state = state
        // 단축키 테이블 — 설정의 keybinding 재정의를 기본 위에 얹고(없으면 기본 그대로) 진단을 로그·노출한다. (DESIGN 7)
        rebuildKeymap(config)
        // 휠 마우스로도 탭바를 좌우로 굴릴 수 있게 — 가로 전용 스크롤뷰에만 적용된다.
        wheelMonitor = WheelScrollBridge.install()
        // 라이트↔다크가 바뀌면 터미널 팔레트를 다시 굽는다(색 폴백이 설정에 구워져 있어 재적용이 필요).
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.runtime?.applyAppearance() }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
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

        // 신호등을 상단바 중앙으로 — 상단바가 표준 타이틀바보다 높아 기본 위치면 위로 붙는다.
        // 시스템이 레이아웃을 되돌리므로 창 이벤트마다 다시 맞춘다(아래 windowDid* 델리게이트).
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        TrafficLights.align(in: window, barHeight: RowHeight.topBar)
        self.window = window

        // 단축키 — 포커스된 터미널이 키를 먼저 먹으므로 로컬 모니터로 가로챈다.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                self.handleShortcut(event) ? nil : event
            }
        }

        // 설정 파일을 감시해 저장 시 자동 재적용한다(재시작 불필요). 콜백은 메인에서 온다.
        configWatcher = ConfigWatcher(fileURL: MuxaConfigLoader.fileURL) { [weak self] in
            self?.reloadConfig()
        }

        NSApp.activate(ignoringOtherApps: true)

        // 세션 복원이 정착된 뒤(초기 렌더 → 활성 스토어의 ensureInitialTerminal 완료) 고아 스크롤백 파일 정리.
        // 미개방 프로젝트의 파일은 savedLayouts가 참조하므로 보존된다(collectScrollbackGarbage 주석). 부작용이라 메인 async로 미룬다.
        DispatchQueue.main.async { [weak state] in state?.collectScrollbackGarbage() }
    }

    /// 설정 파일 변경 감지 시 재로드·재적용 — 파싱은 순수 함수(MuxaConfig.parse) 그대로, 여기선 결과만 반영한다.
    /// 키맵은 새 재정의로 재빌드(로컬 키 모니터가 즉시 새 테이블 사용), 런타임 값은 AppState가 스토어에 전파한다.
    /// sidebar_mode·기본 워크스페이스 경로는 "초기 기본값"이라 라이브 반영하지 않는다(AppState.applyConfig 주석).
    private func reloadConfig() {
        let config = MuxaConfigLoader.load()
        rebuildKeymap(config)
        state?.applyConfig(config)
    }

    /// 설정의 재정의로 키맵을 (재)빌드하고, 감지된 진단을 로그로 남기며 AppState에 노출한다.
    /// 시작·라이브 리로드 두 경로가 공유하는 단일 진실 원천(중복 제거). 부작용(로그·상태 쓰기)은 여기에 격리.
    private func rebuildKeymap(_ config: MuxaConfig) {
        keymap = KeymapResolver(overrides: config.keybindings)
        for diagnostic in keymap.diagnostics {
            keymapLog.warning("키바인딩 경고: \(diagnostic.message, privacy: .public)")
        }
        // 노출값 반영 + 알림 인박스에 시스템 경고로 표면화(사용자가 벨에서 "왜 안 먹지" 확인). dedup은 AttentionLog가.
        state?.surfaceKeymapDiagnostics(keymap.diagnostics)
    }

    /// 로컬 키 모니터의 착지점 — 판정은 KeymapResolver(순수)에 위임하고, 매치되면 실행 후 소비(true),
    /// 미매치면 통과(false → 포커스된 터미널이 먹는다). 우리 창 이벤트만 대상. (DESIGN 7 라우팅 규칙)
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.window === window, let state else { return false }
        guard let action = keymap.resolve(keyCode: Int(event.keyCode),
                                          characters: event.charactersIgnoringModifiers,
                                          flags: event.modifierFlags) else { return false }
        // 빠른 전환기가 열려 있으면 ⌘K만 토글로 받고, 나머지 크롬 단축키는 삼켜 뒤 화면 오조작을 막는다.
        // (평문·Esc는 keymap 미매치라 여기 안 오고 전환기 입력창으로 흘러간다.)
        if state.showQuickSwitch {
            if case .quickSwitch = action { state.toggleQuickSwitch() }
            return true
        }
        // 실행은 AppState.perform에 위임 — 팔레트(⌘K 명령 항목)와 공유하는 단일 진실 원천.
        return state.perform(action)
    }

    /// 최소 메인 메뉴 — App 메뉴에 종료(⌘Q)·가리기(⌘H)만. Edit 메뉴의 ⌘C/⌘V는 터미널
    /// 복사·붙여넣기(ghostty가 직접 처리)를 가로채므로 넣지 않는다.
    /// bare 실행(.app 번들 아님)에선 Info.plist 아이콘이 없어 Dock이 기본 실행 아이콘을 쓴다.
    /// 번들 리소스 AppIcon.png를 런타임에 applicationIconImage로 얹어 Dock·⌘Tab 아이콘을 muxa로. 재생성 = scripts/build-appicon.
    private func setAppIcon() {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        // 메뉴 항목에 앱 이름을 박는다 — 개발 빌드면 "muxa (dev)"라 설치된 앱과 구분된다(AppInfo).
        // (메뉴바 좌측의 볼드 앱 이름은 프로세스명/CFBundleName에서 오므로 여기서 못 바꾼다.)
        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(withTitle: "\(AppInfo.name) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        // ⌘Q는 곧장 terminate로 보내지 않는다 — requestQuit이 먼저 시트로 확인한다(위 주석).
        let quitItem = NSMenuItem(title: "\(AppInfo.name) 종료", action: #selector(requestQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: NSWindowDelegate — 신호등 재정렬
    //
    // 시스템은 리사이즈·활성화·풀스크린 전환 때 타이틀바를 다시 레이아웃하며 신호등을 표준 위치로
    // 되돌린다. 그때마다 상단바 중앙으로 다시 내린다.

    func windowDidResize(_ notification: Notification) { realignTrafficLights(notification) }
    func windowDidBecomeKey(_ notification: Notification) { realignTrafficLights(notification) }
    func windowDidExitFullScreen(_ notification: Notification) { realignTrafficLights(notification) }

    private func realignTrafficLights(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        TrafficLights.align(in: window, barHeight: RowHeight.topBar)
    }

    /// ⌘Q(메뉴) 착지점 — **종료 흐름에 들어가기 전에** 묻는다.
    ///
    /// `applicationShouldTerminate`에서 묻지 않는 이유: 거기서 `.terminateLater`를 반환하는 순간
    /// 앱은 이미 "종료 대기" 상태로 들어가고 런루프가 모달로 바뀐다. 그러면 터미널(Metal) 렌더가
    /// 멈춰 **창이 텅 빈 채로 시트만 떠 있는** 모양이 된다 — 앱이 이미 죽은 뒤 물음창만 남은 꼴이다.
    /// 그래서 종료를 시작하기 전에 시트를 띄우고, 사용자가 확인했을 때만 실제 종료로 넘어간다.
    @objc private func requestQuit() {
        guard state?.config.confirmQuit ?? true else {
            NSApp.terminate(nil)
            return
        }
        guard let window, window.isVisible else {
            NSApp.terminate(nil) // 붙일 창이 없으면 물을 자리도 없다
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "muxa를 종료할까요?"
        alert.informativeText = "실행 중인 터미널 세션이 모두 종료됩니다."
        alert.addButton(withTitle: "종료") // 첫 버튼 = 기본(Enter)
        alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.quitConfirmed = true
            NSApp.terminate(nil)
        }
    }

    /// 종료 확인 — 실행 중인 터미널 세션이 다 닫히므로 실수 종료를 막는다. 설정 confirm_quit=false면 건너뛴다. (DESIGN 4.6)
    ///
    /// ⌘Q는 `requestQuit`이 먼저 물어보고 오므로 여기선 통과시킨다. Dock 우클릭 종료·시스템 종료처럼
    /// 그 경로를 안 거친 종료만 여기서 막는다(그 경우엔 창이 아직 살아 있어 독립 모달로 물어도 어색하지 않다).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitConfirmed { return .terminateNow }
        guard state?.config.confirmQuit ?? true else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "muxa를 종료할까요?"
        alert.informativeText = "실행 중인 터미널 세션이 모두 종료됩니다."
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// 종료 직전 현재 분할 레이아웃을 저장하고 크래시 마커를 지운다(정상 종료 표시).
    /// split/탭 변경은 자체 save를 안 부르므로 여기서 확정. 이 경로를 못 타면 다음 시작에 더티로 잡힌다.
    func applicationWillTerminate(_ notification: Notification) {
        state?.endSession()
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
