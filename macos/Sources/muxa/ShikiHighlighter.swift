import WebKit

/// Shiki 하이라이터 싱글턴 — 오프스크린 WKWebView 1개가 shiki를 딱 1회 로드(init)하고,
/// 코드 → 완성 HTML 변환만 반복 제공한다. 각 코드 탭이 독립 WKWebView로 shiki를 매번
/// 로드/init하던 굼뜸을 없앤다. 표시는 각 탭이 가벼운 loadHTMLString으로 처리.
@MainActor
final class ShikiHighlighter: NSObject, WKNavigationDelegate {
    static let shared = ShikiHighlighter()

    private let webView: WKWebView
    private var ready = false
    private var waiters: [() -> Void] = []

    private override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        if let url = Bundle.module.url(forResource: "code-shell", withExtension: "html", subdirectory: "codeviewer") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// 앱 시작 시 접근만 해두면 백그라운드로 shiki를 미리 로드(첫 파일도 빠르게).
    func warmUp() {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0() }
    }

    /// 코드 → 완성 HTML(줄번호·테마 포함). shiki 로드 전이면 로드 완료를 기다린 뒤 처리.
    func highlight(code: String, language: String?, dark: Bool) async -> String {
        await waitUntilReady()
        let b64 = Data(code.utf8).base64EncodedString()
        do {
            let result = try await webView.callAsyncJavaScript(
                "return await fullHtml(b64, dark, lang)",
                arguments: ["b64": b64, "dark": dark, "lang": language ?? "text"],
                contentWorld: .page
            )
            return (result as? String) ?? ""
        } catch {
            return ""
        }
    }

    private func waitUntilReady() async {
        if ready { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if ready { cont.resume() } else { waiters.append { cont.resume() } }
        }
    }
}
