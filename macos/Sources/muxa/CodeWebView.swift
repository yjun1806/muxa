import SwiftUI
import WebKit

/// diff-viewer JS → Swift 리뷰 코멘트 브리지 메시지. 신뢰 경계: diff HTML 자체가 만든 페이로드만 온다.
enum ReviewBridgeMessage {
    case add(file: String, side: DiffSide, line: Int, text: String)
    case delete(id: String)

    /// postMessage 딕셔너리 → 타입. 필드가 빠지거나 형이 안 맞으면 nil(무시).
    init?(dict: [String: Any]) {
        switch dict["action"] as? String {
        case "add":
            guard let file = dict["file"] as? String, !file.isEmpty,
                  let sideStr = dict["side"] as? String, let side = DiffSide(rawValue: sideStr),
                  let text = dict["text"] as? String else { return nil }
            let line = (dict["line"] as? Int) ?? Int((dict["line"] as? Double) ?? 0)
            self = .add(file: file, side: side, line: line, text: text)
        case "delete":
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            self = .delete(id: id)
        default:
            return nil
        }
    }
}

/// 정적 HTML(코드/diff)을 WKWebView에 그린다. loadHTMLString이라 뷰마다 shiki 로드가 없어 가볍고,
/// md 뷰어와 같은 WKWebView라 Bonsplit keepAllAlive ZStack에서 정상 합성된다(NSTextView 합성 문제 회피).
/// `onMessage`를 주면 diff의 hunk 스테이지 버튼(JS)이 보낸 hunk 인덱스를 Swift로 받고,
/// `onComment`를 주면 줄 코멘트 add/delete 브리지 메시지를 받는다(두 채널은 독립).
/// html이 바뀌어 리로드할 때는 직전 scrollY를 저장했다가 복원해, 라이브 리로드(에이전트 수정)에도 위치가 튀지 않는다.
struct CodeWebView: NSViewRepresentable {
    let html: String
    /// JS → Swift 콜백(hunk 스테이지, 인덱스). nil이면 스테이지 채널을 등록하지 않는다(코드 뷰어는 읽기 전용).
    var onMessage: ((Int) -> Void)?
    /// JS → Swift 콜백(hunk 버리기, 인덱스). nil이면 버리기 채널을 등록하지 않는다.
    var onDiscard: ((Int) -> Void)?
    /// JS → Swift 콜백(리뷰 코멘트 add/delete). nil이면 코멘트 채널을 등록하지 않는다.
    var onComment: ((ReviewBridgeMessage) -> Void)?
    /// 재적용(스테이지·재로딩) 중이면 true — hunk 스테이지 버튼을 시각적으로 비활성(pointer-events off).
    var busy: Bool = false
    /// 이 문서의 실제 파일 경로 — 선택을 IDE에 알릴 때 필요(코드 뷰어).
    var filePath: String = ""
    /// 본문 텍스트 선택(또는 해제) — IDE 통합으로 흘려보낸다(코드는 줄번호가 소스와 거의 일치).
    var onSelection: (IdeSelection) -> Void = { _ in }
    /// 이 문서가 지금 활성(선택된) 서브탭인가 — 활성이 되는 순간 현재 선택을 재보고해 컨텍스트가 따라오게 한다.
    var isSelected: Bool = false

    /// diff HTML의 hunk 스테이지 버튼이 postMessage로 부르는 핸들러 이름.
    static let messageName = "muxaStage"
    /// diff HTML의 hunk 버리기 버튼이 postMessage로 부르는 핸들러 이름.
    static let discardMessageName = "muxaDiscard"
    /// diff HTML의 코멘트 버튼이 postMessage로 부르는 핸들러 이름.
    static let commentMessageName = "muxaComment"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if onMessage != nil {
            config.userContentController.add(context.coordinator, name: CodeWebView.messageName)
        }
        if onDiscard != nil {
            config.userContentController.add(context.coordinator, name: CodeWebView.discardMessageName)
        }
        if onComment != nil {
            config.userContentController.add(context.coordinator, name: CodeWebView.commentMessageName)
        }
        config.userContentController.add(context.coordinator, name: DocSelectionBridge.messageName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // 로드 전 흰 깜빡임 방지
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onMessage = onMessage
        context.coordinator.onDiscard = onDiscard
        context.coordinator.onComment = onComment
        context.coordinator.filePath = filePath
        context.coordinator.onSelection = onSelection
        context.coordinator.setBusy(busy)
        context.coordinator.load(html)
        context.coordinator.applySelected(isSelected) // 활성 전환 시 재보고
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        context.coordinator.onDiscard = onDiscard
        context.coordinator.onComment = onComment
        context.coordinator.filePath = filePath
        context.coordinator.onSelection = onSelection
        context.coordinator.setBusy(busy)
        context.coordinator.load(html)
        context.coordinator.applySelected(isSelected) // 활성 전환 시 재보고
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onMessage: ((Int) -> Void)?
        var onDiscard: ((Int) -> Void)?
        var onComment: ((ReviewBridgeMessage) -> Void)?
        var filePath = ""
        var onSelection: (IdeSelection) -> Void = { _ in }
        private var lastHTML = ""
        private var busy = false
        private var isSelected = false
        private var ready = false
        /// 리로드 직전에 저장한 세로 스크롤 위치 — didFinish에서 복원 후 0으로 되돌린다.
        private var savedScrollY: Double = 0

        /// 활성 서브탭이 됐으면 현재 선택을 강제 재보고 — 컨텍스트가 이 문서로 정확히 따라온다.
        func applySelected(_ sel: Bool) {
            guard sel != isSelected else { return }
            isSelected = sel
            if sel, ready { webView?.evaluateJavaScript(DocSelectionBridge.reportJS) }
        }

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
            ready = true
            webView.evaluateJavaScript(DocSelectionBridge.js) // 선택 → IDE 브리지 주입
            if isSelected { webView.evaluateJavaScript(DocSelectionBridge.reportJS) } // 로드 시 활성이면 즉시 보고
            if savedScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY))")
                savedScrollY = 0
            }
            applyBusy() // 리로드된 문서에 busy 상태 재적용
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == DocSelectionBridge.messageName {
                if let sel = DocSelectionBridge.selection(from: message.body, filePath: filePath) { onSelection(sel) }
                return
            }
            switch message.name {
            case CodeWebView.messageName:
                if let index = Self.hunkIndex(message.body) { onMessage?(index) }
            case CodeWebView.discardMessageName:
                if let index = Self.hunkIndex(message.body) { onDiscard?(index) }
            case CodeWebView.commentMessageName:
                if let dict = message.body as? [String: Any], let msg = ReviewBridgeMessage(dict: dict) {
                    onComment?(msg)
                }
            default:
                break
            }
        }

        /// postMessage 페이로드(Int·Double·String)를 hunk 인덱스로 정규화. 스테이지·버리기 채널이 공유.
        private static func hunkIndex(_ body: Any) -> Int? {
            switch body {
            case let n as Int: return n
            case let d as Double: return Int(d)
            case let s as String: return Int(s)
            default: return nil
            }
        }
    }
}
