import AppKit
import Highlighter

/// 코드 신택스 하이라이트 싱글턴 — HighlighterSwift(highlight.js를 JavaScriptCore로 래핑, 오프라인).
/// JSContext는 스레드 안전이 아니라 전용 직렬 큐에서만 접근한다. 결과는 NSAttributedString.
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private let queue = DispatchQueue(label: "muxa.code-highlighter", qos: .userInitiated)
    private let highlighter = Highlighter()
    private var currentTheme = ""

    private init() {}

    /// 코드를 하이라이트한다(백그라운드 큐에서 호출 권장). 실패 시 평문 attributed string.
    /// theme는 시스템 외관에 맞춰 라이트/다크 CSS를 스위칭한다.
    func highlight(_ code: String, language: String?, dark: Bool) -> NSAttributedString {
        queue.sync {
            let theme = dark ? "atom-one-dark" : "atom-one-light"
            if theme != currentTheme {
                if highlighter?.setTheme(theme, withFont: "Menlo", ofSize: 12) == true {
                    currentTheme = theme
                }
            }
            return highlighter?.highlight(code, as: language, doFastRender: true)
                ?? NSAttributedString(
                    string: code,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: Palette.fg,
                    ]
                )
        }
    }
}
