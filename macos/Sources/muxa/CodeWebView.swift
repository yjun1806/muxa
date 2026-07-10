import SwiftUI
import WebKit

/// 정적 HTML(코드/diff)을 WKWebView에 그린다. loadHTMLString이라 뷰마다 shiki 로드가 없어 가볍고,
/// md 뷰어와 같은 WKWebView라 Bonsplit keepAllAlive ZStack에서 정상 합성된다(NSTextView 합성 문제 회피).
/// `onMessage`를 주면 diff의 hunk 스테이지 버튼(JS)이 보낸 hunk 인덱스를 Swift로 받는다.
/// html이 바뀌어 리로드할 때는 직전 scrollY를 저장했다가 복원해, 라이브 리로드(에이전트 수정)에도 위치가 튀지 않는다.
struct CodeWebView: NSViewRepresentable {
    let html: String
    /// JS → Swift 콜백(hunk 인덱스). nil이면 메시지 핸들러를 등록하지 않는다(코드 뷰어는 읽기 전용).
    var onMessage: ((Int) -> Void)?
    /// 재적용(스테이지·재로딩) 중이면 true — hunk 스테이지 버튼을 시각적으로 비활성(pointer-events off).
    var busy: Bool = false

    /// diff HTML의 hunk 버튼이 postMessage로 부르는 핸들러 이름.
    static let messageName = "muxaStage"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if onMessage != nil {
            config.userContentController.add(context.coordinator, name: CodeWebView.messageName)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // 로드 전 흰 깜빡임 방지
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onMessage = onMessage
        context.coordinator.setBusy(busy)
        context.coordinator.load(html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        context.coordinator.setBusy(busy)
        context.coordinator.load(html)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onMessage: ((Int) -> Void)?
        private var lastHTML = ""
        private var busy = false
        /// 리로드 직전에 저장한 세로 스크롤 위치 — didFinish에서 복원 후 0으로 되돌린다.
        private var savedScrollY: Double = 0

        func load(_ html: String) {
            guard html != lastHTML, let webView else { return }
            let isReload = !lastHTML.isEmpty
            lastHTML = html
            guard isReload else {
                webView.loadHTMLString(html, baseURL: nil)
                return
            }
            // 리로드면 현재 scrollY를 먼저 읽어 저장한 뒤 새 HTML을 싣는다(didFinish에서 복원).
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                self?.savedScrollY = (value as? Double) ?? 0
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        /// 재적용 중 스테이지 버튼 비활성 토글 — html 재생성 없이 data-busy 속성만 바꾼다(리로드 없음).
        func setBusy(_ b: Bool) {
            busy = b
            applyBusy()
        }

        private func applyBusy() {
            webView?.evaluateJavaScript(busy
                ? "document.documentElement.setAttribute('data-busy','1')"
                : "document.documentElement.removeAttribute('data-busy')")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if savedScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY))")
                savedScrollY = 0
            }
            applyBusy() // 리로드된 문서에 busy 상태 재적용
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
