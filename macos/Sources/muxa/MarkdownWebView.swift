import SwiftUI
import WebKit

/// md/HTML 뷰어 본체 — 번들 shell.html(markdown-it·highlight.js·mermaid)을 WKWebView에 로드하고
/// render(base64, dark, raw)로 그린다. 완전 오프라인, 다크/라이트 자동. 읽기 전용.
/// .html 파일은 raw=true로 파싱 없이 원문을 그대로 렌더한다(HTML 뷰어 겸용).
/// 링크 클릭은 shell.html이 네이티브로 넘긴다 — 외부는 브라우저, 로컬 파일은 앱 내 새 탭(onOpenFile).
struct MarkdownWebView: NSViewRepresentable {
    let content: String
    let isRawHTML: Bool
    /// 원본 보기 — 렌더 대신 원문 텍스트를 그대로. md/html 공통.
    var showSource: Bool = false
    /// 상대경로 링크 해석의 기준 — 현재 문서의 디렉토리.
    let baseDir: String
    /// 로컬 파일 링크를 앱 내 뷰어 새 탭으로 연다.
    var onOpenFile: (String) -> Void = { _ in }
    /// 외부 http(s) 링크를 인앱 브라우저 새 탭으로 연다.
    var onOpenURL: (URL) -> Void = { _ in }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Coordinator를 그대로 핸들러로 쓰면 config가 강하게 잡아 순환이 생긴다(Coordinator.webView도 강참조면).
        // webView는 weak로 들고, 핸들러 등록만 Coordinator가 받는다 — 순환 없음.
        config.userContentController.add(context.coordinator, name: "muxaLink")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pending = (content, isRawHTML, showSource)
        if let url = Bundle.module.url(forResource: "shell", withExtension: "html", subdirectory: "mdviewer") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.baseDir = baseDir
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.render(content: content, isRawHTML: isRawHTML, source: showSource)
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.baseDir = baseDir
        c.onOpenFile = onOpenFile
        c.onOpenURL = onOpenURL
        return c
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pending: (String, Bool, Bool)?
        var baseDir = ""
        var onOpenFile: (String) -> Void = { _ in }
        var onOpenURL: (URL) -> Void = { _ in }
        private var ready = false
        private var lastKey = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let (c, raw, source) = pending {
                pending = nil
                render(content: c, isRawHTML: raw, source: source)
            }
        }

        func render(content: String, isRawHTML: Bool, source: Bool) {
            guard ready, let webView else { pending = (content, isRawHTML, source); return }
            // source 플래그를 키에 넣어야 한다 — 안 넣으면 원본 토글 시 content가 같아 재렌더가 스킵된다.
            let key = "\(isRawHTML)|\(source)|\(content.count)|\(content.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            // UTF-8 base64로 전달 — shell의 decodeURIComponent(escape(atob(...)))가 복원한다.
            let b64 = Data(content.utf8).base64EncodedString()
            webView.evaluateJavaScript("render(\"\(b64)\", \(dark), \(isRawHTML), \(source))")
        }

        // shell.html이 넘긴 링크 클릭 — 판정은 순수 함수(resolveMarkdownLink), 실행만 여기서.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "muxaLink", let href = message.body as? String else { return }
            switch resolveMarkdownLink(href: href, baseDir: baseDir) {
            case .external(let url):
                onOpenURL(url)
            case .localFile(let path):
                // 존재하는 파일만 앱 내로. 없으면 무시(깨진 상대 링크가 빈 탭을 만들지 않게).
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                    onOpenFile(path)
                }
            case .ignore:
                break
            }
        }
    }
}
