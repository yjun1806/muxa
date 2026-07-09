import AppKit
import SwiftUI

/// Bonsplit 패인 안에 터미널(TermView)을 넣는 SwiftUI 브리지.
/// Bonsplit이 패인 프레임을 SwiftUI 레이아웃으로 관리하므로, 여기선 TermView를 호스팅만 한다.
/// (수동 setFrame이 없어 제약 엔진 폭주가 발생하지 않는다.)
///
/// onFocus: 터미널 클릭 시 그 패인을 Bonsplit에 포커스시킨다 — 단축키(⌘D/⌘T/⌘W)가
/// 올바른 패인을 대상으로 삼도록. 터미널(NSView)이 클릭을 먼저 먹으므로 SwiftUI tap으론 부족하다.
struct TerminalRepresentable: NSViewRepresentable {
    let term: TermView
    let onFocus: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        // Bonsplit 패인 안에선 컨테이너 크기에 맞춰 autoresize한다 — 그러려면 translates=true여야 한다
        // (TermView.init은 구 수동 레이아웃용으로 false였음).
        term.translatesAutoresizingMaskIntoConstraints = true
        term.autoresizingMask = [.width, .height]
        term.frame = container.bounds
        container.addSubview(term)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        term.onFocus = onFocus // 매 렌더마다 현재 paneId로 갱신(탭 이동 대응)
        if term.superview !== nsView {
            term.removeFromSuperview()
            term.frame = nsView.bounds
            term.autoresizingMask = [.width, .height]
            nsView.addSubview(term)
        }
    }
}
