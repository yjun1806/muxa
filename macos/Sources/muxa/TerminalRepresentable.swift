import AppKit
import SwiftUI

/// 컨테이너가 **창을 얻는 순간** 스스로 재부착하는 호스트 뷰.
///
/// 재부모화가 보류(`.hold`)된 컨테이너는 SwiftUI 렌더만으론 다시 깨어나지 못한다(자기잠금).
/// 재시도 트리거는 시간(폴링)이 아니라 AppKit 이벤트에서 온다 — 창에 붙는 그 순간이 결정적 시점이다.
///
/// 무엇을 붙일지는 **클로저 캡처가 아니라 프로퍼티**로 들고 있는다. SwiftUI는 같은 호스트 뷰를 재사용해
/// 다른 탭의 TermView를 그리게 하는데(updateNSView), 캡처해 두면 창을 되찾는 순간 **옛 TermView**가
/// 되붙어 탭바와 화면이 어긋난다.
final class TermHostView: NSView {
    var term: TermView?
    var windowId: String = WindowID.main.rawValue

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let term else { return }
        TerminalRepresentable.adopt(term, self, windowId)
    }
}

/// Bonsplit 패인 안에 터미널(TermView)을 넣는 SwiftUI 브리지.
/// Bonsplit이 패인 프레임을 SwiftUI 레이아웃으로 관리하므로, 여기선 TermView를 호스팅만 한다.
/// (수동 setFrame이 없어 제약 엔진 폭주가 발생하지 않는다.)
///
/// onFocus: 터미널 클릭 시 그 패인을 Bonsplit에 포커스시킨다 — 단축키(⌘D/⌘T/⌘W)가
/// 올바른 패인을 대상으로 삼도록. 터미널(NSView)이 클릭을 먼저 먹으므로 SwiftUI tap으론 부족하다.
///
/// windowId: 이 뷰 트리를 그리는 창. term의 소유 창과 다르면 **아무것도 하지 않는다** —
/// 서비스 도크처럼 메인에만 있는 호출부는 기본값을 그대로 쓴다.
struct TerminalRepresentable: NSViewRepresentable {
    let term: TermView
    var windowId: String = WindowID.main.rawValue
    let onFocus: () -> Void

    func makeNSView(context: Context) -> TermHostView {
        let host = TermHostView()
        update(host)
        return host
    }

    func updateNSView(_ nsView: TermHostView, context: Context) {
        term.onFocus = onFocus // 매 렌더마다 현재 paneId로 갱신(탭 이동 대응)
        update(nsView)
    }

    /// 호스트가 지금 그려야 할 대상을 새기고 붙인다 — 창을 잃었다 되찾을 때도 이 값이 진실이다.
    private func update(_ host: TermHostView) {
        host.term = term
        host.windowId = windowId
        Self.adopt(term, host, windowId)
    }

    /// 멱등 재부모화. 판정은 순수 함수(TermAttach.decide)에 위임한다.
    ///
    /// `.hold`(화면 밖 컨테이너가 산 터미널을 강탈하려는 경우)는 **영구 포기가 아니다** —
    /// 그 컨테이너가 창을 얻으면 TermHostView.viewDidMoveToWindow가 다시 부른다.
    static func adopt(_ term: TermView, _ container: NSView, _ windowId: String) {
        let decision = TermAttach.decide(isOwner: term.ownerWindowId == windowId,
                                         alreadyChild: term.superview === container,
                                         containerInWindow: container.window != nil,
                                         termInWindow: term.window != nil)
        guard decision == .attach else { return }
        term.removeFromSuperview()
        // Bonsplit 패인 안에선 컨테이너 크기에 맞춰 autoresize한다 — 그러려면 translates=true여야 한다
        // (TermView.init은 구 수동 레이아웃용으로 false였음).
        term.translatesAutoresizingMaskIntoConstraints = true
        term.frame = container.bounds
        term.autoresizingMask = [.width, .height]
        container.addSubview(term)
    }
}
