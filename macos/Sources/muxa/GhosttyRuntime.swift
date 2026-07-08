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
        runtime.action_cb = { _, _, action in
            // M0: 앱 크롬 액션(타이틀 변경·벨 등)은 처리하지 않는다
            _ = action
            return false
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
