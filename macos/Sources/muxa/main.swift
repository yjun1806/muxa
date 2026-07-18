import AppKit
import Bonsplit
import Carbon.HIToolbox
import GhosttyKit
import os
import SwiftUI

/// 키바인딩 재정의 경고 로그 채널. 사용자가 표면(콘솔·Console.app)에서 "왜 안 먹지"를 추적할 수 있게 한다.
private let keymapLog = Logger(subsystem: "com.muxa.app", category: "keybind")

// muxa — SwiftUI 크롬 + AppKit(GhosttyKit) 터미널 하이브리드 (ARCHITECTURE.md D16).
// AppKit이 NSWindow·activation을 제어(raw 실행에도 창이 확실히 뜬다)하고,
// NSHostingView로 SwiftUI UI를 그 안에 임베드한다. Ghostty와 같은 구조.

guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
    fatalError("ghostty_init failed")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var runtime: GhosttyRuntime?
    private var state: AppState?
    /// 창을 만들고 없애는 유일한 경계(모델 ⇄ NSWindow reconcile). 메인 창도 여기 등록된다.
    private let host = WindowHost()
    private var mainWindow: NSWindow? { host.window(.main) }
    private var keyMonitor: Any?
    /// 휠 마우스 → 가로 전용 스크롤 영역(탭바·서브탭 바) 브리지. 앱 수명 동안 유지.
    private var wheelMonitor: Any?
    /// 단축키 판정 테이블 — 설정 로드 후 재정의를 얹어 교체한다(그전까진 기본 테이블). 라이브 리로드로 다시 교체된다.
    private var keymap = KeymapResolver.default
    /// 설정 파일 감시자 — 저장 시 자동 재적용(재시작 불필요). 부작용은 이 경계 타입에 격리. (ARCHITECTURE 4.6)
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

        // 탭바 툴팁(분할 버튼·탭 제목·오디오 배지)을 muxa 팝오버 칩으로 — 예전엔 Bonsplit이
        // NSToolTip(`.help()`)으로 그려 뷰를 감쌀 수 없어 **앱 전역** `NSInitialToolTipDelay=250`
        // 해킹을 깔았는데, 그 탓에 앱의 모든 툴팁이 즉시 떠 거슬렸다. 이제 포크가 툴팁 표시를
        // 호스트에 위임하므로(`BonsplitTooltipHost`) 전역 지연 해킹은 제거 — 나머지 툴팁은 시스템 기본.
        BonsplitTooltipHost.render = { view, text in AnyView(view.muxaTip(text)) }

        // 분할 칸 사이 divider 위 리사이즈 커서. Bonsplit은 이 훅이 **설정됐을 때만** divider의
        // 확장 효과 영역(두께 + hitExpansion)에 커서를 걸고, unset이면 AppKit 네이티브(그려진 1pt
        // 선 위에서만)로 폴백한다 — 그 1pt는 사실상 못 짚어 커서가 안 바뀌는 것처럼 보인다.
        // vertical divider(좌우 칸 구분) = 좌우 리사이즈, horizontal divider(상하 칸 구분) = 상하 리사이즈.
        BonsplitDividerCursors.vertical = .resizeLeftRight
        BonsplitDividerCursors.horizontal = .resizeUpDown

        setAppIcon() // Dock 아이콘 — bare 실행(.app 번들 아님)이라 런타임에 직접 설정
        ShikiHighlighter.shared.warmUp() // 코드 하이라이터를 미리 로드 — 첫 코드 파일도 즉시 뜨게
        NotificationService.shared.requestAuthorizationIfPossible() // 데스크톱 알림 권한(번들일 때만)
        setupMainMenu() // ⌘Q(종료)·⌘H(가리기) — 메뉴가 없으면 ⌘Q가 안 묶인다

        // muxa 설정(~/.config/muxa/config) 로드 — 없으면 전부 기본값. 폰트·테마는 ghostty config 재사용(GhosttyRuntime). (ARCHITECTURE 4.6)
        let config = MuxaConfigLoader.load()

        // 개발빌드는 워크트리마다 저장소가 갈린다(AppInfo.devKey) — 이 저장소의 출처를 찍어두고,
        // 주인(워크트리)이 사라진 유령 저장소를 청소한다. 릴리스에선 둘 다 무동작.
        MuxaSupportDir.stampOrigin()
        MuxaSupportDir.collectGarbage()

        // 저장된 세션 복원(없으면 설정의 기본 경로/현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState(app: app, config: config)
        state.load()
        state.beginSession() // 크래시 마커 arm + 직전 더티 종료 여부 판정(노출용)
        // 첫 워크스페이스 경로 — 판정은 순수(InitialWorkspacePath). 번들 실행의 cwd는 `/`라 그대로 쓰면
        // 첫 화면이 파일시스템 루트가 된다.
        state.ensureInitial(path: InitialWorkspacePath.resolve(
            configured: config.defaultWorkspacePath,
            currentDir: SystemPaths.currentDir,
            isBundled: Bundle.main.bundleIdentifier != nil,
            home: SystemPaths.home
        ))
        // 데모 스크린샷 모드(MUXA_DEMO) — tmux·라이브 훅 없이 리치 상태를 코드로 시드하고,
        // 서비스 폴링은 건너뛴다(폴링이 돌면 시드한 서비스 상태를 실측이 덮는다).
        var demoSeeded = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["MUXA_DEMO"] != nil {
            state.seedDemo()
            demoSeeded = true
        }
        #endif
        if !demoSeeded {
            // 좀비 청소 — 서비스 tmux 세션은 muxa를 꺼도 살아남는다(그게 존재 이유다). 그 대가로 등록이
            // 사라진 세션이 포트를 문 채 남을 수 있어, 복원 직후 등록과 대조해 쓸어낸다. (Service.swift)
            state.collectServiceGarbage()
            // 저장된 서비스 재기동(살아 있으면 멱등) + 상태 폴링 시작. 청소 뒤에 와야 방금 지운 세션을
            // 되살리지 않는다.
            state.startServices()
        }
        state.startNotifyServer() // 훅 알림 소켓 리스너 시작 — `muxa notify`가 결정론적 신호를 보낸다
        // 시스템 알림 클릭 → 프로젝트 활성 + Git 패널(원클릭 검토 동선). 라우팅 소유는 AppState.
        NotificationService.shared.onActivate = { [weak state] ctx in
            state?.revealActivity(projectId: ctx.projectId, tabId: ctx.tabId)
        }
        // 알림 권한이 거부돼 있으면 인박스에 표면화한다 — 조용한 Dock 바운스 폴백은 "고장"으로 읽힌다.
        NotificationService.shared.onDenied = { [weak state] in state?.surfaceNotificationsDisabled() }
        self.state = state
        // 단축키 테이블 — 설정의 keybinding 재정의를 기본 위에 얹고(없으면 기본 그대로) 진단을 로그·노출한다. (ARCHITECTURE 7)
        rebuildKeymap(config)
        // 휠 마우스로도 탭바를 좌우로 굴릴 수 있게 — 가로 전용 스크롤뷰에만 적용된다.
        wheelMonitor = WheelScrollBridge.install()
        // 라이트↔다크가 바뀌면 터미널 팔레트를 다시 굽는다(색 폴백이 설정에 구워져 있어 재적용이 필요).
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.runtime?.applyAppearance() }
        }

        // 크롬(상단바·사이드바) + 활성 워크스페이스(Bonsplit 탭바·분할)를 SwiftUI로 렌더.
        let hosting = NSHostingView(rootView: ContentView(state: state, home: SystemPaths.home))
        // safe-area를 끈다 — 안 그러면 SwiftUI가 타이틀바 아래로 콘텐츠를 밀어 상단바가
        // 신호등과 다른 줄로 분리된다(두 줄). 꺼야 콘텐츠가 타이틀바 밑까지 올라와 한 줄이 된다.
        hosting.safeAreaRegions = []

        // 창 설정·델리게이트(신호등 정렬·포커스 계약)는 전부 MuxaWindowController가 쥔다.
        let main = MuxaWindowController(id: .main, content: hosting)
        // 메인 창 닫기 = 앱 종료다 — 시트로 먼저 묻고(confirmQuit), 끄기로 했다면 창을 닫는 대신
        // 바로 terminate한다. 창만 닫고 살아 있으면 Dock 아이콘만 남은 좀비가 된다.
        main.shouldClose = { [weak self] in
            guard let self else { return true }
            if quitConfirmed { return true } // 이미 시트에서 확인받았다 — 종료 흐름이 창을 닫는 중
            guard state.config.confirmQuit else {
                NSApp.terminate(nil)
                return false
            }
            requestQuit() // 시트로 확인 — 사용자가 확인하면 terminate가 창까지 정리한다
            return false  // 지금은 닫지 않는다(취소했을 때 창이 남아야 한다)
        }
        host.register(main)
        // 분리 창 본문 — 사이드바 없는 프로젝트 루트. 창을 만드는 건 WindowHost(reconcile)이고,
        // 여기서는 "그 창에 무엇을 그릴지"만 알려준다.
        host.makeProjectContent = { id in
            let view = NSHostingView(rootView: ProjectWindowView(state: state, windowId: id,
                                                                 home: SystemPaths.home))
            view.safeAreaRegions = [] // 메인 창과 같은 이유 — 상단바가 신호등과 한 줄이 되게
            return view
        }
        // 분리 창이 닫히면 그 프로젝트를 메인으로 되돌린다(무손실 재합치기 — D30).
        host.onProjectWindowClosed = { [weak state] id in state?.rejoin(id) }
        // 분리 창의 위치·크기 영속 — 모델엔 즉시, 디스크엔 디바운스(AppState.recordFrame).
        host.onFrameChange = { [weak state] id, frame in state?.recordFrame(id, frame) }
        state.windowHost = host
        main.show()
        #if DEBUG
        if demoSeeded {
            // 데모 스크린샷용 — 넉넉한 창 크기로 고정(손쉬운 사용 권한 없이 창을 키운다).
            main.window.setFrame(NSRect(x: 0, y: 0, width: 1480, height: 940), display: true)
            main.window.center()
        }
        #endif
        // 복원된 분리 창을 실물로 띄운다 — load()는 모델만 채운다(reconcile은 경계가 한다).
        state.syncWindows()

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
        DispatchQueue.main.async { [weak state] in
            state?.collectScrollbackGarbage()
            state?.collectTerminalSessionGarbage() // 닫힌 탭이 남긴 tmux 세션 정리(L3)
        }
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
    /// 미매치면 통과(false → 포커스된 터미널이 먹는다). 우리 창 이벤트만 대상. (ARCHITECTURE 7 라우팅 규칙)
    private func handleShortcut(_ event: NSEvent) -> Bool {
        // 우리가 아는 창(메인·분리 창)의 이벤트만 가로챈다 — 모르는 창(FloatingPanel의 메뉴·팝오버,
        // 시트)은 그대로 통과시킨다. 실행 대상 창을 WindowID로 넘겨 그 창의 스토어에만 적용한다.
        guard let eventWindow = event.window, let windowId = host.id(for: eventWindow),
              let state else { return false }
        // 닫기 확인 배너가 떠 있으면 그 키(⌘W/⌘B/⌘C/esc)를 배너 결정으로 먼저 소비한다 —
        // keymap.resolve보다 앞서야 ⌘W가 .closeTab이 아니라 "완전 종료"로 간다.
        if state.closeConfirmShortcut(keyCode: Int(event.keyCode),
                                      characters: event.charactersIgnoringModifiers,
                                      flags: event.modifierFlags, in: windowId) { return true }
        guard let action = keymap.resolve(keyCode: Int(event.keyCode),
                                          characters: event.charactersIgnoringModifiers,
                                          flags: event.modifierFlags) else { return false }
        // 빠른 전환기가 열려 있으면 ⌘K만 토글로 받고, 나머지 크롬 단축키는 삼켜 뒤 화면 오조작을 막는다.
        // (평문·Esc는 keymap 미매치라 여기 안 오고 전환기 입력창으로 흘러간다.)
        // **메인 창에서만.** 전환기는 메인에만 뜨는데(v1 — §6) 게이트가 전역이면, 팔레트를 열어 둔 채
        // 분리 창으로 넘어간 순간 그 창의 단축키가 전부 삼켜진다(사용자에겐 "키가 죽었다").
        if windowId.isMain, state.showQuickSwitch {
            if case .quickSwitch = action { state.toggleQuickSwitch() }
            return true
        }
        // 실행은 AppState.perform에 위임 — 팔레트(⌘K 명령 항목)와 공유하는 단일 진실 원천.
        return state.perform(action, in: windowId)
    }

    /// 메인 메뉴 — App 메뉴(종료 ⌘Q·가리기 ⌘H) + 표준 편집 메뉴(⌘X/C/V/A).
    /// bare 실행(.app 번들 아님)에선 Info.plist 아이콘이 없어 Dock이 기본 실행 아이콘을 쓴다.
    /// 번들 리소스 AppIcon.png를 런타임에 applicationIconImage로 얹어 Dock·⌘Tab 아이콘을 muxa로. 재생성 = scripts/build-appicon.
    private func setAppIcon() {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        // 메뉴바 좌측의 볼드 앱 이름 = **첫 메뉴 항목의 title**. 비워 두면 macOS가 프로세스명으로 대신 채운다
        // (그래서 dev 실행도 "muxa"로 보였다). 여기에 이름을 박아야 "muxa (dev)"로 뜬다(AppInfo).
        let appItem = NSMenuItem()
        appItem.title = AppInfo.name
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: AppInfo.name)
        // 버전 확인 경로 — "어느 빌드에서 터졌나"를 사용자가 말할 수 있어야 한다(Info.plist 버전을 표시).
        appMenu.addItem(withTitle: "\(AppInfo.name) 정보",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // 설정은 텍스트 파일뿐이다(~/.config/muxa/config) — 파일이 없으면 주석 달린 기본본을 만들어 연다.
        // 이 항목이 없으면 설정이 존재한다는 사실조차 알 수 없다.
        let configItem = NSMenuItem(title: "설정 파일 열기…", action: #selector(openConfigFile), keyEquivalent: ",")
        configItem.target = self
        appMenu.addItem(configItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(AppInfo.name) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        // 문제 보고 동선 — 앱이 터져도 사용자가 개발자에게 줄 수 있는 자료가 없었다(로그 파일·내보내기 0건).
        let diagItem = NSMenuItem(title: "진단 정보 복사", action: #selector(copyDiagnostics), keyEquivalent: "")
        diagItem.target = self
        appMenu.addItem(diagItem)
        let supportItem = NSMenuItem(title: "지원 폴더 열기", action: #selector(openSupportFolder), keyEquivalent: "")
        supportItem.target = self
        appMenu.addItem(supportItem)
        appMenu.addItem(.separator())
        // ⌘Q는 곧장 terminate로 보내지 않는다 — requestQuit이 먼저 시트로 확인한다(위 주석).
        let quitItem = NSMenuItem(title: "\(AppInfo.name) 종료", action: #selector(requestQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu

        // 표준 편집 메뉴 — WKWebView 코드/md 뷰어·로그 뷰(Text)에서 ⌘C 복사가 되게 하려면
        // `copy:`를 responder에 꽂아줄 메뉴 키 등가물이 필요하다(WKWebView는 스스로 ⌘C를 안 먹는다).
        // 터미널은 안전하다 — TermView가 copy:/paste: 셀렉터를 구현하지 않아 포커스 시 항목이 자동 비활성되고,
        // ghostty가 ⌘C/⌘V를 키 이벤트로 직접 처리한다(TermView.performKeyEquivalent). autoenablesItems가
        // responder 체인을 보고 항목을 켜고 끄므로 nil 타깃 표준 셀렉터만 건다.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // 명령 메뉴 — 앱의 실제 명령(새 터미널·분할·패널…)이 지금까지 키 모니터와 마우스에만 있었다.
        // 메뉴바는 macOS에서 명령의 정본이자 VoiceOver(VO+M)·'키보드 단축키' 재바인딩의 유일한 표면이다.
        // 목록·단축키는 **QuickCommandCatalog 단일 출처**를 그대로 구워 쓴다(표를 두 번 적지 않는다).
        let commandItem = NSMenuItem()
        mainMenu.addItem(commandItem)
        let commandMenu = NSMenu(title: "명령")
        let paletteItem = NSMenuItem(title: "명령 팔레트…", action: #selector(openCommandPalette), keyEquivalent: "k")
        paletteItem.target = self
        commandMenu.addItem(paletteItem)
        commandMenu.addItem(.separator())
        for (i, command) in QuickCommandCatalog.items.enumerated() {
            let item = NSMenuItem(title: command.title, action: #selector(runCatalogCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i // 카탈로그 인덱스 — KeymapAction은 @objc로 못 실어 나른다
            if let hint = command.shortcutHint, let key = MenuShortcut.parse(hint) {
                item.keyEquivalent = key.equivalent
                item.keyEquivalentModifierMask = key.modifiers
            }
            commandMenu.addItem(item)
        }
        commandItem.submenu = commandMenu

        // 창 메뉴 — 분리 창을 뒤로 보내거나 최소화했을 때 **되찾을 유일한 수단**이다(시스템이 열린 창
        // 목록을 여기에 자동으로 채운다). 닫기(⌘W)는 넣지 않는다 — ⌘W는 탭 닫기 단축키다.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "창")
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "모두 앞으로 가져오기",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// 메뉴의 명령 항목 착지점 — 실행은 키 모니터·팔레트와 같은 경로(AppState.perform)로 보낸다.
    @objc private func runCatalogCommand(_ sender: NSMenuItem) {
        guard let state, QuickCommandCatalog.items.indices.contains(sender.tag),
              let action = QuickCommandCatalog.items[sender.tag].action else { return }
        _ = state.perform(action, in: focusedWindowId)
    }

    @objc private func openCommandPalette() {
        state?.toggleQuickSwitch()
    }

    /// 설정 파일을 연다 — 없으면 주석 달린 기본본을 1회 만들고(빈 파일이면 뭘 쓸 수 있는지 알 수 없다) 연다.
    @objc private func openConfigFile() {
        NSWorkspace.shared.open(MuxaConfigLoader.ensureFile())
    }

    /// 명령을 적용할 창 — 키 창이 우리 창이면 그 창, 아니면 메인(키 모니터와 같은 규칙).
    private var focusedWindowId: WindowID {
        guard let window = NSApp.keyWindow, let id = host.id(for: window) else { return .main }
        return id
    }

    /// 메뉴 명령의 키 등가물이 **우리 창이 키일 때만** 먹게 한다.
    /// 시트·팝오버(FloatingPanel)가 떠 있을 때 ⌘W·⌘T가 뒤 화면을 조작하면 안 된다 —
    /// 키 모니터도 같은 이유로 모르는 창의 이벤트를 통과시킨다(handleShortcut).
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let ours = menuItem.action == #selector(runCatalogCommand(_:))
            || menuItem.action == #selector(openCommandPalette)
        guard ours else { return true }
        guard let window = NSApp.keyWindow else { return false }
        return host.id(for: window) != nil
    }

    /// 진단 정보(버전·macOS·지원 폴더·직전 종료)를 클립보드로 — 조립은 순수(Diagnostics.report), 여기선 부작용만.
    @objc private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary
        let text = Diagnostics.report(
            name: AppInfo.name,
            version: info?["CFBundleShortVersionString"] as? String ?? "dev",
            build: info?["CFBundleVersion"] as? String ?? "-",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            supportDir: MuxaSupportDir.url.path,
            lastLaunchWasDirty: state?.lastLaunchWasDirty ?? false
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 지원 폴더(state.v4.json·스크롤백)를 Finder로 — 사용자가 자료를 직접 첨부할 수 있게.
    @objc private func openSupportFolder() {
        NSWorkspace.shared.open(MuxaSupportDir.url)
    }

    /// 앱이 활성화될 때마다 알림 권한을 시스템에 되묻는다 — 사용자가 중간에 켰을 수도, 껐을 수도 있다.
    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationService.shared.refreshAuthorization()
        // 배지를 다는 판정("앱이 백그라운드면 안 보인다")과 짝이 되는 해제 경로. 없으면 눈앞에 띄워 둔
        // 프로젝트에 ●와 Dock 카운트가 영영 남는다 — 다 보이는 걸 두고 기다리라는 신호가 된다.
        state?.clearVisibleBadges()
    }

    /// 분리 창만 닫혀도 종료 판정에 끌려가지 않게 false. 종료는 메인 창 닫기·⌘Q만이 시작한다
    /// (메인 창 닫기 = 앱 종료 — MuxaWindowController.shouldClose).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
        // 시트는 언제나 메인 창에 붙인다 — 분리 창에서 ⌘Q를 눌러도 같은 자리에서 묻는다.
        guard let window = mainWindow, window.isVisible else {
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

    /// 종료 확인 — 실행 중인 터미널 세션이 다 닫히므로 실수 종료를 막는다. 설정 confirm_quit=false면 건너뛴다. (ARCHITECTURE 4.6)
    ///
    /// **여기까지 오는 건 창을 거치지 않는 종료뿐이다** — Dock 우클릭 종료, 시스템 로그아웃·재시동.
    /// ⌘Q는 `requestQuit`, 창 닫기는 `windowShouldClose`가 각각 **시트**로 먼저 묻고 오므로
    /// (`quitConfirmed`) 여기선 통과한다. 즉 사용자가 일상적으로 보는 확인창은 시트 하나로 통일돼 있고,
    /// 이 모달은 붙일 창이 없는 경로의 최후 방어선이다.
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
