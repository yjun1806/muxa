import GhosttyKit
import SwiftUI

/// SwiftUI에 GhosttyKit 터미널 서피스(AppKit NSView)를 임베드한다.
/// TermView가 viewDidMoveToWindow에서 스스로 first responder를 잡으므로 IME·키가 유지된다.
struct TerminalSurface: NSViewRepresentable {
    let app: ghostty_app_t
    let cwd: String?

    func makeNSView(context: Context) -> TermView {
        TermView(app: app, cwd: cwd)
    }

    func updateNSView(_ nsView: TermView, context: Context) {}
}
