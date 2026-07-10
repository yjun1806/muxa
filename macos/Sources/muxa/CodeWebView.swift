import SwiftUI
import WebKit

/// 정적 HTML(코드/diff)을 WKWebView에 그린다. loadHTMLString이라 뷰마다 shiki 로드가 없어 가볍고,
/// md 뷰어와 같은 WKWebView라 Bonsplit keepAllAlive ZStack에서 정상 합성된다(NSTextView 합성 문제 회피).
/// `onMessage`를 주면 diff의 hunk 스테이지 버튼(JS)이 보낸 hunk 인덱스를 Swift로 받는다.
struct CodeWebView: NSViewRepresentable {
    let html: String
    /// JS → Swift 콜백(hunk 인덱스). nil이면 메시지 핸들러를 등록하지 않는다(코드 뷰어는 읽기 전용).
    var onMessage: ((Int) -> Void)?

    /// diff HTML의 hunk 버튼이 postMessage로 부르는 핸들러 이름.
    static let messageName = "muxaStage"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if onMessage != nil {
            config.userContentController.add(context.coordinator, name: CodeWebView.messageName)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // 로드 전 흰 깜빡임 방지
        context.coordinator.webView = webView
        context.coordinator.onMessage = onMessage
        context.coordinator.load(html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        context.coordinator.load(html)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onMessage: ((Int) -> Void)?
        private var lastHTML = ""

        func load(_ html: String) {
            guard html != lastHTML, let webView else { return }
            lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == CodeWebView.messageName else { return }
            let index: Int?
            switch message.body {
            case let n as Int: index = n
            case let d as Double: index = Int(d)
            case let s as String: index = Int(s)
            default: index = nil
            }
            if let index { onMessage?(index) }
        }
    }
}
