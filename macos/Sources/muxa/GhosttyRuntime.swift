import AppKit
import GhosttyKit

/// libghostty 앱 인스턴스와 런타임 콜백을 소유한다.
///
/// 콜백은 C 함수 포인터라 캡처가 불가능하다 — userdata로 인스턴스를 넘겨 복원한다.
/// wakeup이 오면 메인 스레드에서 `ghostty_app_tick`을 돌리는 것이 계약의 핵심.
final class GhosttyRuntime {
    private(set) var app: ghostty_app_t?

    init?() {
        // 사용자 ghostty 설정(폰트·테마)이 있으면 그대로 재사용한다 (DESIGN.md D12 보너스)
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
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
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(cString: text), forType: .string)
            }
        }
        runtime.close_surface_cb = { _, _ in
            // M0: 셸 종료 시 앱도 종료
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        guard let app = ghostty_app_new(&runtime, config) else { return nil }
        self.app = app
        ghostty_app_set_focus(app, true)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    deinit {
        if let app { ghostty_app_free(app) }
    }
}
