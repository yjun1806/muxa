import SwiftUI
import WebKit

/// md/HTML 뷰어 본체 — 번들 shell.html(markdown-it·highlight.js·mermaid)을 WKWebView에 로드하고
/// render(base64, dark, raw)로 그린다. 완전 오프라인, 다크/라이트 자동. 읽기 전용.
/// .html 파일은 raw=true로 파싱 없이 원문을 그대로 렌더한다(HTML 뷰어 겸용).
struct MarkdownWebView: NSViewRepresentable {
    let content: String
    let isRawHTML: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pending = (content, isRawHTML)
        if let url = Bundle.module.url(forResource: "shell", withExtension: "html", subdirectory: "mdviewer") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(content: content, isRawHTML: isRawHTML)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var pending: (String, Bool)?
        private var ready = false
        private var lastKey = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let (c, raw) = pending {
                pending = nil
                render(content: c, isRawHTML: raw)
            }
        }

        func render(content: String, isRawHTML: Bool) {
            guard ready, let webView else { pending = (content, isRawHTML); return }
            let key = "\(isRawHTML)|\(content.count)|\(content.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            // UTF-8 base64로 전달 — shell의 decodeURIComponent(escape(atob(...)))가 복원한다.
            let b64 = Data(content.utf8).base64EncodedString()
            webView.evaluateJavaScript("render(\"\(b64)\", \(dark), \(isRawHTML))")
        }
    }
}
