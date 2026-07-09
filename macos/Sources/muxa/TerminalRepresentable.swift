import AppKit
import SwiftUI

/// Bonsplit 패인 안에 터미널(TermView)을 넣는 SwiftUI 브리지.
/// Bonsplit이 패인 프레임을 SwiftUI 레이아웃으로 관리하므로, 여기선 TermView를 그대로 호스팅만 한다.
/// (수동 setFrame이 없어 제약 엔진 폭주가 발생하지 않는다.)
struct TerminalRepresentable: NSViewRepresentable {
    let term: TermView

    func makeNSView(context: Context) -> NSView {
        // 컨테이너로 감싸 SwiftUI가 프레임을 관리(autoresizing)하게 하고, TermView를 채운다.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = true
        term.translatesAutoresizingMaskIntoConstraints = true
        term.autoresizingMask = [.width, .height]
        term.frame = container.bounds
        container.addSubview(term)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if term.superview !== nsView {
            term.removeFromSuperview()
            term.frame = nsView.bounds
            term.autoresizingMask = [.width, .height]
            nsView.addSubview(term)
        }
    }
}
