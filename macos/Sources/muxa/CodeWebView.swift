import SwiftUI
import WebKit

/// 정적 HTML(코드/diff)을 WKWebView에 그린다. loadHTMLString이라 뷰마다 shiki 로드가 없어 가볍고,
/// md 뷰어와 같은 WKWebView라 Bonsplit keepAllAlive ZStack에서 정상 합성된다(NSTextView 합성 문제 회피).
struct CodeWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground") // 로드 전 흰 깜빡임 방지
        context.coordinator.webView = webView
        context.coordinator.load(html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var webView: WKWebView?
        private var lastHTML = ""

        func load(_ html: String) {
            guard html != lastHTML, let webView else { return }
            lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
