import SwiftUI
import WebKit

/// 인앱 브라우저 본체 — WKWebView를 감싸고 BrowserTab 상태와 양방향으로 잇는다.
/// - 명령(뒤로·앞으로·새로고침·URL 로드)은 tab의 훅으로 받아 WKWebView에 전달.
/// - 관측(현재 URL·제목·네비 가능 여부·로딩)은 델리게이트에서 tab에 반영.
/// lazy 로드: 서브탭이 처음 보일(shouldLoad) 때만 initialURL을 로드한다 — 비활성 탭은 네트워크를 쓰지 않는다.
struct BrowserWebView: NSViewRepresentable {
    let tab: BrowserTab
    /// 이 서브탭이 화면에 보이는가 — false→true가 되는 첫 순간에만 초기 URL을 로드한다.
    let shouldLoad: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView

        // 명령 훅을 이 webView로 연결(약참조로 잡아 순환을 피한다).
        tab.goBackAction = { [weak webView] in webView?.goBack() }
        tab.goForwardAction = { [weak webView] in webView?.goForward() }
        tab.reloadAction = { [weak webView] in webView?.reload() }
        tab.stopAction = { [weak webView] in webView?.stopLoading() }
        tab.loadAction = { [weak webView] url in webView?.load(URLRequest(url: url)) }

        maybeLoad(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        maybeLoad(webView)
    }

    /// 보이는 상태가 됐고 아직 로드하지 않았으면 최초 1회 로드.
    private func maybeLoad(_ webView: WKWebView) {
        guard shouldLoad, !tab.hasStartedLoading else { return }
        tab.hasStartedLoading = true
        webView.load(URLRequest(url: tab.initialURL))
    }

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let tab: BrowserTab
        weak var webView: WKWebView?

        init(tab: BrowserTab) { self.tab = tab }

        private func syncState(_ webView: WKWebView) {
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            if let url = webView.url {
                tab.currentURL = url
                // 사용자가 주소창을 편집 중이면 입력을 덮어쓰지 않는다.
                if !tab.isEditingAddress { tab.addressText = url.absoluteString }
            }
            if let title = webView.title, !title.isEmpty { tab.pageTitle = title }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            tab.isLoading = true
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            syncState(webView)
            tab.onNavigated() // currentURL 확정 → 스냅샷 갱신(복원 정확도)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            syncState(webView)
        }

        // http(s)는 웹뷰에서, 그 외 스킴(mailto·tel 등)은 시스템 앱으로 넘긴다.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow); return
            }
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        // target=_blank(새 창) 링크는 같은 웹뷰에서 연다 — 별도 창을 만들지 않는다.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
