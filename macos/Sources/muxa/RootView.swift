import AppKit
import GhosttyKit
import SwiftUI

/// 창 contentView — SwiftUI 크롬(사이드바·탭바)과 AppKit 터미널 호스트를 형제로 담는다. (DESIGN.md D16)
///
/// 터미널을 SwiftUI(NSHostingView) 안에 두면 분할 시 내부 레이아웃이 SwiftUI 제약 패스를
/// 재귀 무효화해 창이 크래시한다. 그래서 터미널은 형제 AppKit 뷰로 분리하고,
/// SwiftUI는 "터미널 자리"의 프레임만 좌표(onTerminalFrame)로 알려준다.
final class RootView: NSView {
    private let terminalHost: WorkspaceHostView
    private let chrome: NSView
    private var termFrame: CGRect = .zero

    init(app: ghostty_app_t, state: AppState, home: String) {
        let host = WorkspaceHostView(app: app, state: state)
        self.terminalHost = host

        // 크롬은 나중에 self를 캡처해야 해서, 먼저 placeholder로 만들고 아래에서 rootView를 넣는다.
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        self.chrome = hosting

        super.init(frame: .zero)
        wantsLayer = true

        hosting.rootView = AnyView(
            ContentView(app: app, state: state, home: home) { [weak self] rect in
                self?.setTerminalFrame(rect)
            }
        )
        // 터미널 호스트는 수동 프레임으로 배치한다 — Auto Layout 제약 엔진에서 제외해야
        // split(자식 다수)에서 자동 생성 제약과 수동 프레임이 충돌해 제약 패스가 폭주(크래시)하지 않는다.
        host.translatesAutoresizingMaskIntoConstraints = false

        addSubview(hosting) // 아래: 크롬
        addSubview(host) // 위: 터미널(크롬의 빈 자리에 겹쳐 보인다)

        host.observeAndSync()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true } // 좌상단 원점 — SwiftUI "root" 좌표계와 일치

    /// SwiftUI가 알려준 터미널 자리(크롬 루트 좌표)를 형제 터미널 호스트에 그대로 적용한다.
    private func setTerminalFrame(_ rect: CGRect) {
        guard rect != termFrame else { return }
        termFrame = rect
        terminalHost.frame = rect
    }

    override func layout() {
        super.layout()
        if chrome.frame != bounds { chrome.frame = bounds }
        if termFrame != .zero, terminalHost.frame != termFrame { terminalHost.frame = termFrame }
    }
}
