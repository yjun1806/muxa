import SwiftUI
import WebKit

/// 코드 뷰어 표시 뷰 — 공유 ShikiHighlighter(오프스크린, init 1회)에서 완성 HTML을 받아
/// 가벼운 loadHTMLString으로 렌더한다(자기 뷰는 shiki 로드 안 함 → 파일 열기 즉각). 읽기 전용.
struct CodeWebView: NSViewRepresentable {
    let code: String
    let language: String?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        context.coordinator.webView = webView
        context.coordinator.render(code: code, language: language)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(code: code, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var webView: WKWebView?
        private var lastKey = ""

        func render(code: String, language: String?) {
            let key = "\(language ?? "")|\(code.count)|\(code.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            Task { @MainActor in
                let html = await ShikiHighlighter.shared.highlight(code: code, language: language, dark: dark)
                webView?.loadHTMLString(html, baseURL: nil)
            }
        }
    }
}
