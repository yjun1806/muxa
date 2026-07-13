import AppKit
import SwiftUI

/// 커스텀 컨텍스트 메뉴를 띄우는 경계 타입 — 떠 있는 패널(NSPanel) 하나를 재사용해 열고 닫는다.
/// 창 안 오버레이가 아니라 별도 패널인 이유: 사이드바처럼 좁은 영역에서 열려도 창 밖으로 펼쳐질 수 있고,
/// ghostty surface(NSView) 위에 확실히 뜨기 때문이다.
///
/// 닫힘 조건 = 바깥 클릭 · Esc · 항목 선택 · 앱 비활성화. 시스템 메뉴가 공짜로 주던 것 중
/// 화면 경계 클램프는 여기서 직접 처리한다(접근성·방향키 네비는 미지원).
@MainActor
final class MuxaMenuWindow {
    static let shared = MuxaMenuWindow()

    private var panel: NSPanel?
    private var monitors: [Any] = []
    /// 앱이 비활성화되면(⌘Tab 등) 메뉴를 닫는 관찰자 — 마우스 이벤트가 없는 전환 경로라 모니터로는 못 잡는다.
    private var resignObserver: NSObjectProtocol?
    /// 메뉴를 열기 직전의 key 창 — 닫을 때 포커스를 돌려준다(터미널 입력이 죽지 않게).
    private weak var previousKey: NSWindow?
    /// 메뉴가 떠 있는 동안 유지돼야 하는 호출부 상태(예: 사이드바 hover peek) 해제 훅.
    private var onClose: (() -> Void)?

    private init() {}

    var isOpen: Bool { panel != nil }

    /// 스크린 좌표 지점에 메뉴를 띄운다. `onClose`는 닫힐 때 1회 호출(호출부의 열림 표시 해제용).
    func show(_ items: [MuxaMenuItem], at point: NSPoint, onClose: (() -> Void)? = nil) {
        dismiss()
        self.onClose = onClose

        let view = MuxaMenuView(items: items) { [weak self] in self?.dismiss() }
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = MenuPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // 그림자는 SwiftUI 쪽에서 그린다(둥근 모서리에 맞춰야 해서)
        panel.contentView = hosting
        panel.setFrameOrigin(Self.origin(for: hosting.fittingSize, at: point))

        previousKey = NSApp.keyWindow
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installMonitors(for: panel)
    }

    func dismiss() {
        guard let panel else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel.orderOut(nil)
        self.panel = nil
        // 포커스 복원은 우리가 아직 활성 앱일 때만. 다른 앱을 클릭해 닫힌 경우에 orderFront를 부르면
        // 방금 클릭한 앱 위로 muxa 창이 솟아오른다.
        if NSApp.isActive { previousKey?.makeKeyAndOrderFront(nil) }
        previousKey = nil
        onClose?()
        onClose = nil
        // 항목 탭 처리는 이 패널의 이벤트 디스패치 안에서 돈다 — 마지막 참조를 지금 놓으면 자기 이벤트를
        // 처리하는 도중 창이 해제될 수 있다. 해제를 다음 런루프로 미룬다.
        DispatchQueue.main.async { _ = panel }
    }

    /// 메뉴 바깥 클릭·Esc·앱 비활성화를 감시한다. 패널 안 클릭은 메뉴 자신이 처리하므로 통과시킨다.
    private func installMonitors(for panel: NSPanel) {
        // 바깥 클릭은 메뉴를 닫는 데만 쓰고 아래로 흘리지 않는다(시스템 메뉴와 같은 동작) —
        // 메뉴를 닫으려던 클릭이 밑의 버튼까지 누르면 안 된다.
        let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard event.window !== panel else { return event }
            MainActor.assumeIsolated { self?.dismiss() }
            return nil
        }
        let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.dismiss() }
            return nil
        }
        // 앱 밖(다른 앱·데스크톱) 클릭 — 로컬 모니터가 못 보는 경로.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        monitors = [mouse, key, global].compactMap { $0 }

        // ⌘Tab처럼 마우스 없이 앱을 떠나는 경로 — 패널이 .popUpMenu 레벨이라 그냥 두면 다른 앱 위에 남는다.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    /// 커서 기준 오른쪽-아래로 펼치되, 화면 밖으로 나가면 반대로 접는다(macOS 메뉴 관례).
    private static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return point }
        var x = point.x
        var y = point.y - size.height // 스크린 좌표는 좌하단 원점 — 아래로 펼치면 origin이 내려간다
        if x + size.width > visible.maxX { x = point.x - size.width }   // 오른쪽 넘침 → 왼쪽으로
        if y < visible.minY { y = point.y }                             // 아래 넘침 → 위로
        x = min(max(x, visible.minX), max(visible.maxX - size.width, visible.minX))
        y = min(max(y, visible.minY), max(visible.maxY - size.height, visible.minY))
        return NSPoint(x: x, y: y)
    }
}

/// borderless 패널은 기본적으로 key가 되지 못한다 — hover·Esc를 받으려면 key가 돼야 한다.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 비활성 창의 첫 클릭이 "창 활성화"에 먹히지 않게 — 메뉴는 한 번의 클릭으로 항목이 선택돼야 한다.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor @preconcurrency required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 미지원") }
}

// MARK: - 우클릭 캡처

extension View {
    /// 우클릭을 스크린 좌표로 받는다. 좌클릭은 그대로 아래 뷰(버튼)로 흘려보낸다.
    /// (⌃-클릭은 AppKit이 leftMouseDown으로 보내므로 여기 오지 않는다 — 크롬 UI에선 우클릭만 지원한다.)
    func onRightClick(perform action: @escaping (NSPoint) -> Void) -> some View {
        overlay(RightClickCatcher(onRightClick: action))
    }
}

/// 좌클릭은 투명하고 우클릭만 잡는 얇은 오버레이. 히트테스트를 현재 이벤트 종류로 갈라 이를 구현한다.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (NSPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? CatcherView)?.onRightClick = onRightClick
    }

    private final class CatcherView: NSView {
        var onRightClick: ((NSPoint) -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(NSEvent.mouseLocation)
        }

        /// 우클릭 이벤트일 때만 자신을 히트 대상으로 내민다 — 좌클릭은 아래 SwiftUI 버튼이 받는다.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}
