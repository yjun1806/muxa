import AppKit

/// ghostty의 클립보드 쓰기를 **한 번만 가로채는** 장치.
///
/// 스크롤백 VT 덤프는 `write_screen_file:copy,vt` 바인딩 액션으로 얻는데, 이 액션은 결과 파일 경로를
/// **클립보드에 써서** 돌려준다. 그대로 두면 캡처할 때마다 사용자가 복사해 둔 내용이 조용히 사라진다
/// — 저장은 수시로 일어나므로 사실상 클립보드를 못 쓰게 된다.
///
/// 그래서 캡처 구간 동안만 write_clipboard 콜백을 가로채 값을 가져오고, NSPasteboard에는 아무것도
/// 쓰지 않는다(복구할 것도 남기지 않는다).
@MainActor
enum ClipboardCapture {
    private static var pending: String?
    private static var isCapturing = false

    /// `action`을 실행하는 동안 클립보드 쓰기를 가로챈다. 가로챈 문자열을 돌려준다(없으면 nil).
    static func intercepting(_ action: () -> Void) -> String? {
        isCapturing = true
        pending = nil
        defer { isCapturing = false; pending = nil }
        action()
        return pending
    }

    /// write_clipboard 콜백에서 호출 — 가로채는 중이면 값을 삼키고 true를 돌려준다(붙여넣기 보드 미변경).
    static func consume(_ text: String) -> Bool {
        guard isCapturing else { return false }
        pending = text
        return true
    }
}
