import AppKit
import GhosttyKit

/// libghostty 앱 인스턴스와 런타임 콜백을 소유한다.
///
/// 콜백은 C 함수 포인터라 캡처가 불가능하다 — userdata로 인스턴스를 넘겨 복원한다.
/// wakeup이 오면 메인 스레드에서 `ghostty_app_tick`을 돌리는 것이 계약의 핵심.
final class GhosttyRuntime {
    private(set) var app: ghostty_app_t?

    init?() {
        guard let config = Self.makeConfig(dark: Self.systemIsDark) else { return nil }
        defer { ghostty_config_free(config) }

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { userdata in
            guard let userdata else { return }
            let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { runtime.tick() }
        }
        runtime.action_cb = { _, target, action in
            // 스크롤백 검색 액션만 처리(⌘F). 나머지 앱 크롬 액션은 무시.
            // 서피스 userdata(=TermView) 복원은 read_clipboard_cb와 동일 패턴.
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let userdata = ghostty_surface_userdata(target.target.surface)
            else { return false }
            let view = Unmanaged<TermView>.fromOpaque(userdata).takeUnretainedValue()

            switch action.tag {
            case GHOSTTY_ACTION_START_SEARCH:
                let needle = action.action.start_search.needle.flatMap { String(cString: $0) }
                DispatchQueue.main.async { view.onStartSearch(needle) }
                return true
            case GHOSTTY_ACTION_END_SEARCH:
                DispatchQueue.main.async { view.onEndSearch() }
                return true
            case GHOSTTY_ACTION_SEARCH_TOTAL:
                // ssize_t, -1 = 미확정 센티넬. 무가드 UInt 캐스팅 금지.
                let total = action.action.search_total.total
                DispatchQueue.main.async { view.onSearchTotal(total >= 0 ? Int(total) : nil) }
                return true
            case GHOSTTY_ACTION_SEARCH_SELECTED:
                let selected = action.action.search_selected.selected
                DispatchQueue.main.async { view.onSearchSelected(selected >= 0 ? Int(selected) : nil) }
                return true
            // A(알림/완료 감지): 백그라운드 탭·프로젝트에 배지(●) + (번들이면) macOS 알림.
            // payload const char*는 콜백 반환 후 무효 → main.async 전에 String으로 복사한다.
            case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
                let n = action.action.desktop_notification
                let title = n.title.flatMap { String(cString: $0) } ?? ""
                let body = n.body.flatMap { String(cString: $0) } ?? ""
                DispatchQueue.main.async { view.onDesktopNotification(title: title, body: body) }
                return true
            case GHOSTTY_ACTION_COMMAND_FINISHED:
                let c = action.action.command_finished
                let code = c.exit_code >= 0 ? Int(c.exit_code) : nil // -1 = 미보고
                let duration = c.duration
                DispatchQueue.main.async { view.onCommandFinished(exitCode: code, duration: duration) }
                return true
            case GHOSTTY_ACTION_RING_BELL:
                // 배지만 부수적으로 울리고, 엔진 기본 벨(사운드·시각벨)은 유지하려 false 반환.
                DispatchQueue.main.async { view.onBell() }
                return false
            case GHOSTTY_ACTION_PROGRESS_REPORT:
                // 진행률은 완료 신호가 아니라 이번 범위 밖 — 엔진에 위임.
                return false
            // 출력 heartbeat(에이전트 상태 추정, DESIGN 4.5). RENDER는 고빈도라 스로틀 게이트를 먼저 통과시키고,
            // 통과분만 메인에서 신호로 넘긴다. false 반환 — 엔진 기본 렌더 파이프라인은 그대로 둔다.
            case GHOSTTY_ACTION_RENDER:
                if view.shouldEmitRenderHeartbeat() {
                    DispatchQueue.main.async { view.emitOutputHeartbeat() }
                }
                return false
            // 탭별 작업 디렉터리 추적(OSC 7) — 세션 저장 시 이 경로에서 새 셸로 복원(DESIGN 4.2).
            // pwd const char*는 콜백 반환 후 무효 → main.async 전에 String으로 복사한다.
            case GHOSTTY_ACTION_PWD:
                guard let pwd = action.action.pwd.pwd.flatMap({ String(cString: $0) }), !pwd.isEmpty
                else { return false }
                DispatchQueue.main.async { view.onPwdChange(pwd) }
                return true
            // 탭 자동 명명(OSC 0/2 SET_TITLE·명시적 SET_TAB_TITLE) — 셸/앱이 보낸 제목으로 탭 이름을 갱신한다.
            // title const char*는 콜백 반환 후 무효 → main.async 전에 String으로 복사한다.
            // 수동 지정 탭은 store가 덮지 않게 판정하므로 여기선 값만 넘긴다.
            case GHOSTTY_ACTION_SET_TITLE:
                let title = action.action.set_title.title.flatMap { String(cString: $0) } ?? ""
                DispatchQueue.main.async { view.onSetTitle(title) }
                return true
            case GHOSTTY_ACTION_SET_TAB_TITLE:
                let title = action.action.set_tab_title.title.flatMap { String(cString: $0) } ?? ""
                DispatchQueue.main.async { view.onSetTitle(title) }
                return true
            // 커서 모양(텍스트 위 I-beam·링크 위 손가락·resize) — 안 받으면 커서가 영원히 화살표로 남는다.
            case GHOSTTY_ACTION_MOUSE_SHAPE:
                let shape = action.action.mouse_shape
                DispatchQueue.main.async { view.setMouseShape(shape) }
                return true
            // 타이핑 중 커서 숨김(마우스를 움직이면 다시 나타난다).
            case GHOSTTY_ACTION_MOUSE_VISIBILITY:
                let visible = action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE
                DispatchQueue.main.async { view.setMouseVisibility(visible) }
                return true
            default:
                return false
            }
        }
        runtime.read_clipboard_cb = { userdata, _, state in
            // userdata는 서피스 쪽 userdata = TermView
            guard let userdata, let state else { return false }
            let view = Unmanaged<TermView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = view.surface else { return false }
            let str = NSPasteboard.general.string(forType: .string) ?? ""
            str.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }
        runtime.confirm_read_clipboard_cb = { userdata, str, state, _ in
            // M0: 확인 다이얼로그 없이 그대로 승인한다
            guard let userdata, let state else { return }
            let view = Unmanaged<TermView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = view.surface else { return }
            ghostty_surface_complete_clipboard_request(surface, str, state, true)
        }
        runtime.write_clipboard_cb = { _, _, content, len, _ in
            guard let content, len > 0 else { return }
            // 첫 콘텐츠(text/plain)만 사용
            if let text = content.pointee.data {
                let s = String(cString: text)
                // 스크롤백 VT 덤프 중이면 이 write는 파일 경로다 — 가로채고 클립보드는 건드리지 않는다.
                // (안 그러면 저장할 때마다 사용자가 복사해 둔 내용이 사라진다.)
                if MainActor.assumeIsolated({ ClipboardCapture.consume(s) }) { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }
        runtime.close_surface_cb = { userdata, _ in
            // 셸 종료(exit) → 앱 전체가 아니라 그 서피스가 속한 탭만 닫는다(B1).
            // userdata는 서피스 쪽 userdata = TermView (read_clipboard_cb와 동일 패턴).
            guard let userdata else { return }
            let view = Unmanaged<TermView>.fromOpaque(userdata).takeUnretainedValue()
            guard let tabId = view.tabId else { return }
            DispatchQueue.main.async { view.onRequestClose?(tabId) }
        }

        guard let app = ghostty_app_new(&runtime, config) else { return nil }
        self.app = app
        ghostty_app_set_focus(app, true)
        // 현재 시스템 외관을 ghostty에 알린다(theme = light:,dark: 설정 시 자동 전환에 사용).
        ghostty_app_set_color_scheme(app, Self.systemIsDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }

    /// ghostty 설정 하나를 만든다 — 시작 시와 외관 전환 시가 같은 코드를 쓴다(색의 단일 출처).
    ///
    /// 시스템 외관에 맞춘 배경/전경 폴백을 먼저 깔고, 사용자 config(`~/.config/ghostty/config`)가
    /// theme를 지정하면 load_default_files가 덮는다(사용자 우선). 설정이 없으면 ghostty 기본 테마가
    /// 다크라, 라이트 시스템에서도 터미널만 다크로 어긋나므로 muxa 팔레트에 맞춰 폴백한다.
    private static func makeConfig(dark: Bool) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        let fallback = dark ? darkPalette : lightPalette
        fallback.withCString { ghostty_config_load_string(config, $0, UInt(strlen($0)), "muxa-fallback") }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        return config
    }

    /// 시스템 외관(라이트↔다크)이 바뀌었을 때 터미널 색을 다시 맞춘다.
    ///
    /// `set_color_scheme`만으로는 부족하다 — 배경/전경 폴백은 **설정에 구운 값**이라 설정을 다시
    /// 만들어 넣어야(`app_update_config`) 살아 있는 터미널의 색이 바뀐다. 사용자 ghostty config가
    /// 색을 지정했다면 그 값이 여전히 우선한다(makeConfig의 로드 순서).
    func applyAppearance() {
        guard let app else { return }
        let dark = Self.systemIsDark
        if let config = Self.makeConfig(dark: dark) {
            ghostty_app_update_config(app, config)
            ghostty_config_free(config)
        }
        ghostty_app_set_color_scheme(app, dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }

    // 터미널 ANSI 16색 폴백 — cmux 기본 테마(Apple System Colors)와 동일 팔레트. 색의 단일 출처.
    // 사용자 ~/.config/ghostty/config가 theme/palette를 지정하면 load_default_files가 덮어 우선한다.
    // 0~7 표준, 8~15 밝은 변형. 배경/전경만 muxa 크롬(Palette.bg/fg)에 맞춰 라이트/다크가 다르다.
    private static let lightPalette = """
    palette = 0=#1a1a1a
    palette = 1=#cc372e
    palette = 2=#26a439
    palette = 3=#cdac08
    palette = 4=#0869cb
    palette = 5=#9647bf
    palette = 6=#479ec2
    palette = 7=#98989d
    palette = 8=#464646
    palette = 9=#ff453a
    palette = 10=#32d74b
    palette = 11=#e5bc00
    palette = 12=#0a84ff
    palette = 13=#bf5af2
    palette = 14=#69c9f2
    palette = 15=#ffffff
    background = #ffffff
    foreground = #1f2937
    """

    private static let darkPalette = """
    palette = 0=#1a1a1a
    palette = 1=#cc372e
    palette = 2=#26a439
    palette = 3=#cdac08
    palette = 4=#0869cb
    palette = 5=#9647bf
    palette = 6=#479ec2
    palette = 7=#98989d
    palette = 8=#464646
    palette = 9=#ff453a
    palette = 10=#32d74b
    palette = 11=#ffd60a
    palette = 12=#0a84ff
    palette = 13=#bf5af2
    palette = 14=#76d6ff
    palette = 15=#ffffff
    background = #1b1b1d
    foreground = #e4e4e7
    """

    /// 현재 시스템 외관이 다크인가 — 터미널 폴백 테마·color scheme 판정.
    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    deinit {
        if let app { ghostty_app_free(app) }
    }
}
