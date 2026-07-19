import SwiftUI
import WebKit

/// 문서 diff 뷰어의 WebView 호스트.
///
/// `loadFileURL(allowingReadAccessTo:)`로 **Resources 루트**를 열어준다 — diffdoc이 mdviewer의
/// markdown-it·hljs·본문 CSS를 형제 경로로 참조하기 때문이다(`loadHTMLString(baseURL: nil)`이면
/// 로컬 서브리소스가 전부 조용히 실패한다).
///
/// Swift→JS는 **`callAsyncJavaScript(arguments:)`만** 쓴다. 문자열 보간으로 소스를 끼워 넣으면
/// 에이전트가 쓴 문서 안의 따옴표·백슬래시가 그대로 스크립트가 된다 — 그 경로를 아예 만들지 않는다.
struct DocDiffWebView: NSViewRepresentable {
    let oldSource: String
    let newSource: String
    let dark: Bool
    let density: DocDiffDensity
    /// 리뷰 코멘트 브리지(기존 규약 재사용). nil이면 채널을 안 연다.
    var onComment: ((ReviewBridgeMessage) -> Void)?
    /// 계산 결과 보고 — 통계·소요 시간·강등 여부.
    var onResult: ((DocDiffResult) -> Void)?

    static let commentMessageName = "muxaComment"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if onComment != nil {
            // 핸들러를 직접 add하면 strong 참조로 순환이 생긴다 — weak proxy를 끼운다.
            config.userContentController.add(WeakScriptProxy(context.coordinator),
                                             name: Self.commentMessageName)
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        if web.responds(to: Selector(("setInspectable:"))) { web.isInspectable = true }
        #endif
        context.coordinator.web = web
        if let shell = Self.shellURL, let root = Self.resourcesRoot {
            web.loadFileURL(shell, allowingReadAccessTo: root)
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pushIfReady()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static var resourcesRoot: URL? { Bundle.module.resourceURL }
    static var shellURL: URL? { Bundle.module.url(forResource: "shell", withExtension: "html", subdirectory: "diffdoc") }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: DocDiffWebView
        weak var web: WKWebView?
        private var loaded = false
        /// 마지막으로 보낸 payload — 같은 내용을 다시 밀지 않는다(리렌더 폭주 방지).
        private var lastKey: String?

        init(_ parent: DocDiffWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            lastKey = nil
            pushIfReady()
        }

        func pushIfReady() {
            guard loaded, let web else { return }
            let key = "\(parent.oldSource.hashValue):\(parent.newSource.hashValue):\(parent.dark)"
            if key == lastKey {
                // 내용은 같고 밀도만 바뀐 경우 — 다시 계산하지 않는다.
                web.callAsyncJavaScript("return setDocDiffDensity(density);",
                                        arguments: ["density": parent.density.rawValue],
                                        in: nil, in: .page) { _ in }
                return
            }
            lastKey = key
            let args: [String: Any] = [
                "payload": [
                    "old64": Data(parent.oldSource.utf8).base64EncodedString(),
                    "new64": Data(parent.newSource.utf8).base64EncodedString(),
                    "dark": parent.dark,
                    "density": parent.density.rawValue,
                    "theme": DocDiffTheme.payload(dark: parent.dark)
                ] as [String: Any]
            ]
            web.callAsyncJavaScript("return renderDocDiff(payload);", arguments: args,
                                    in: nil, in: .page) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let v):
                    self.parent.onResult?(DocDiffResult(json: v as? String))
                case .failure(let e):
                    // 계산이 죽어도 화면을 에러로 만들지 않는다 — 상위가 통합 뷰로 강등한다.
                    self.parent.onResult?(DocDiffResult(failure: e.localizedDescription))
                }
            }
        }

        nonisolated func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let msg = ReviewBridgeMessage(dict: dict) else { return }
            Task { @MainActor in self.parent.onComment?(msg) }
        }
    }
}

/// 스크립트 핸들러를 weak로 감싸는 프록시 — `add(_:name:)`이 handler를 strong으로 잡아
/// 코디네이터↔컨트롤러 순환 참조가 생기는 걸 끊는다.
private final class WeakScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// 문서 diff 표시 밀도 — **두 단**이다.
///
/// 리뷰에 필요한 건 "결과물이 어떤 모습인가"와 "뭘 건드렸나" 둘 다인데, 지금까지의 diff는
/// 후자만 줬다. 한 토글로 오가게 하는 게 이 뷰어의 절반이다.
///
/// **Word의 중간 단(Simple Markup)은 두지 않는다.** 두 이유로 이 화면에선 성립하지 않는다:
/// ① **삭제를 표현할 자리가 없다.** 본문을 깨끗이 두려면 삭제된 문단을 숨겨야 하는데, 그러면
///    그 블록에 달린 레일까지 함께 사라져 "바뀐 곳"이라면서 정작 삭제된 곳이 안 보인다.
///    Word는 줄 단위 문서라 여백 막대가 남지만, 렌더된 문서에서 사라진 문단은 자리 자체가 없다.
/// ② **미니맵이 이미 그 일을 한다.** 스크롤바 옆 변경 위치 레일이 "어디가 바뀌었나"를 항상
///    보여주므로, 같은 목적의 밀도 단계는 중복이다.
enum DocDiffDensity: String, CaseIterable, Identifiable {
    /// 최종본 — 변경 표시 0. 커밋 diff에서도 "그 시점의 문서"를 볼 수 있는 유일한 자리.
    case clean
    /// 상세 — 인라인 강조 전부(기본).
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: return "최종본"
        case .full: return "변경 표시"
        }
    }

    var help: String {
        switch self {
        case .clean: return "변경 표시 없이 완성된 문서만 — 결과물이 어떤 모습인지 본다"
        case .full: return "추가·삭제·수정을 문서 위에 전부 표시"
        }
    }

    var icon: String {
        switch self {
        case .clean: return "doc.plaintext"
        case .full: return "text.magnifyingglass"
        }
    }
}

/// 계산 결과 — 도구줄이 통계를 보여주고, 실패면 상위가 통합 뷰로 강등한다.
struct DocDiffResult: Equatable {
    var ok: Bool = false
    var ms: Int = 0
    var inserted = 0, deleted = 0, modified = 0, moved = 0
    /// Highlight API가 실제로 쓰였나 — false면 폴백 경로(구 macOS)다.
    var highlight = true
    var failure: String?

    var totalChanges: Int { inserted + deleted + modified + moved }

    init(failure: String) { self.failure = failure }

    init(json: String?) {
        guard let json, let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            failure = "결과를 읽지 못했습니다"
            return
        }
        ok = (o["ok"] as? Bool) ?? false
        ms = (o["ms"] as? Int) ?? 0
        highlight = (o["highlight"] as? Bool) ?? true
        if let s = o["stats"] as? [String: Any] {
            inserted = (s["inserted"] as? Int) ?? 0
            deleted = (s["deleted"] as? Int) ?? 0
            modified = (s["modified"] as? Int) ?? 0
            moved = (s["moved"] as? Int) ?? 0
        }
    }
}
