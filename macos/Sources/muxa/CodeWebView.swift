import SwiftUI
import WebKit

/// 코드 뷰어 본체 — 번들 code-shell.html(Shiki, VSCode 문법)로 하이라이트. 완전 오프라인, 다크/라이트 자동.
/// Shiki JS RegExp 엔진이라 wasm 없음 → WKWebView 특수 설정 불필요. 읽기 전용, 줄번호(CSS 카운터).
struct CodeWebView: NSViewRepresentable {
    let code: String
    let language: String?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pending = (code, language)
        if let url = Bundle.module.url(forResource: "code-shell", withExtension: "html", subdirectory: "codeviewer") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(code: code, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var pending: (String, String?)?
        private var ready = false
        private var lastKey = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let (c, l) = pending {
                pending = nil
                render(code: c, language: l)
            }
        }

        func render(code: String, language: String?) {
            guard ready, let webView else { pending = (code, language); return }
            let key = "\(language ?? "")|\(code.count)|\(code.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            let b64 = Data(code.utf8).base64EncodedString()
            let lang = language ?? "text"
            webView.evaluateJavaScript("render(\"\(b64)\", \(dark), \"\(lang)\")")
        }
    }
}
