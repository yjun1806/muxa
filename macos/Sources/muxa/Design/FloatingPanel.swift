import AppKit
import SwiftUI

/// 창 위에 떠 있는 표면(커스텀 메뉴·푸터 팝오버)의 **공통 크롬과 공통 창**.
///
/// 메뉴와 팝오버는 같은 것이다 — "칩/버튼에서 나와 잠깐 떠 있다가 바깥을 누르면 사라지는 판".
/// 그런데 메뉴는 직접 그린 NSPanel이고 팝오버는 시스템 `.popover`라, 같은 푸터에서 열리는데도
/// 모서리·배경·그림자·화살표가 제각각이었다. 둘의 **표면(`floatingPanel()`)과 창(`FloatingPanelHost`)을
/// 여기 한 곳에 모은다** — 그래야 한 세트로 보인다.

// MARK: - 표면(크롬)

extension View {
    /// 떠 있는 판의 표면 — 배경·모서리·테두리·그림자, 그리고 **그림자가 잘리지 않을 만큼의 바깥 여백**.
    ///
    /// 여백(`Elevation.margin`)이 핵심이다. 창은 이 여백까지 포함해 잡히고 배경이 투명이므로,
    /// 그림자는 창 안에서 자연스럽게 흩어져 사라진다. 여백이 그림자 반경보다 좁으면 흩어지던 그림자가
    /// 창 경계에서 **직각으로 잘려** 판 주위에 네모난 회색 테가 생긴다 — 그게 "이상한 그림자"의 정체다.
    func floatingPanel() -> some View {
        background(Color.pPanel)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.pBorder, lineWidth: RowHeight.hairline))
            // 두 겹으로 나눈다: 넓고 옅은 그림자가 "떠 있음"을, 좁고 짙은 그림자가 판의 윤곽을 만든다.
            // 한 겹으로 같은 존재감을 내려면 반경을 키워야 하고, 그러면 판 주변이 뿌옇게 번진다.
            .shadow(color: .black.opacity(Elevation.keyOpacity),
                    radius: Elevation.keyRadius, y: Elevation.keyOffsetY)
            .shadow(color: .black.opacity(Elevation.ambientOpacity),
                    radius: Elevation.ambientRadius, y: Elevation.ambientOffsetY)
            .padding(Elevation.margin)
    }
}

// MARK: - 놓을 자리

/// 떠 있는 판을 어디에 놓을지 — 좌표는 전부 스크린 기준. 판의 **콘텐츠**(그림자 여백 제외) 기준으로 센다.
enum PanelPlacement {
    /// 커서 지점에서 오른쪽-아래로 펼친다(컨텍스트 메뉴 관례).
    case menu(NSPoint)
    /// 앵커(칩·버튼)의 **위쪽**에 가로 중앙을 맞춰 띄운다. 위가 좁으면 아래로 뒤집는다.
    case above(NSRect)
}

// MARK: - 창

/// 떠 있는 판 하나를 열고 닫는 경계 타입 — 패널(NSPanel)·이벤트 모니터·포커스 복원을 소유한다.
///
/// 창 안 오버레이가 아니라 별도 패널인 이유: 사이드바·푸터처럼 좁은 영역에서 열려도 창 밖으로 펼쳐질 수 있고,
/// ghostty surface(NSView) 위에 확실히 뜨기 때문이다.
///
/// 닫힘 조건 = 바깥 클릭 · Esc · 항목 선택 · 앱 비활성화. 시스템이 공짜로 주던 것 중
/// 화면 경계 클램프·콘텐츠 크기 추종은 여기서 직접 처리한다(접근성·방향키 네비는 미지원).
@MainActor
final class FloatingPanelHost {
    private var panel: NSPanel?
    private var placement: PanelPlacement = .menu(.zero)
    private var monitors: [Any] = []
    /// 앱이 비활성화되면(⌘Tab 등) 닫는 관찰자 — 마우스 이벤트가 없는 전환 경로라 모니터로는 못 잡는다.
    private var resignObserver: NSObjectProtocol?
    /// 열기 직전의 key 창 — 닫을 때 포커스를 돌려준다(터미널 입력이 죽지 않게).
    private weak var previousKey: NSWindow?
    /// 떠 있는 동안 유지돼야 하는 호출부 상태(예: 열림 표시) 해제 훅.
    private var onClose: (() -> Void)?

    var isOpen: Bool { panel != nil }

    /// 판을 띄운다. `onClose`는 닫힐 때 1회 호출(호출부의 열림 표시 해제용).
    /// 내용은 `floatingPanel()` 표면이 이미 입혀진 뷰여야 한다.
    func show(_ content: some View, at placement: PanelPlacement, onClose: (() -> Void)? = nil) {
        dismiss()
        self.onClose = onClose
        self.placement = placement

        let hosting = PanelHostingView(rootView: AnyView(content))
        hosting.setFrameSize(hosting.fittingSize)

        let panel = KeyPanel(
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
        self.panel = panel

        // 내용이 나중에 자라도(비동기 미리보기·상태 갱신) 창이 따라간다 — 시스템 팝오버가 해주던 일.
        hosting.onIdealSizeChange = { [weak self] size in self?.resize(to: size) }

        reposition()
        previousKey = NSApp.keyWindow
        if Self.animates {
            // 페이드 + 6pt 위로 솟아오르며 등장 — 판이 "칩에서 떠올랐다"는 인상을 준다.
            // 자리(target)는 reposition이 이미 정했다. 살짝 아래에서 시작해 제자리로 민다.
            let target = panel.frame.origin
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - Self.enterSlide))
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.enterDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        installMonitors(for: panel)
    }

    func dismiss() {
        guard let panel else { return }
        // 상호작용은 즉시 끊는다(닫히는 중 클릭이 판에 먹히지 않게).
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        self.panel = nil

        // 포커스 복원은 우리가 아직 활성 앱일 때만. 다른 앱을 클릭해 닫힌 경우에 orderFront를 부르면
        // 방금 클릭한 앱 위로 muxa 창이 솟아오른다.
        let prev = previousKey
        let close = onClose
        previousKey = nil
        onClose = nil
        // 열림 플래그는 **즉시** 내린다(페이드를 기다리지 않는다) — 안 그러면 exit 애니메이션(100ms) 사이
        // 같은 칩을 다시 열었을 때, 사라지던 판의 onClose가 새로 연 판의 바인딩을 꺼버린다.
        // 재진입 dismiss(바인딩 false → onChange → dismiss)는 panel이 이미 nil이라 곧바로 반환한다.
        close?()
        let finish = {
            panel.orderOut(nil)
            if NSApp.isActive { prev?.makeKeyAndOrderFront(nil) }
            // 항목 탭 처리는 이 패널의 이벤트 디스패치 안에서 돈다 — 마지막 참조를 지금 놓으면 자기
            // 이벤트를 처리하는 도중 창이 해제될 수 있다. 해제를 다음 런루프로 미룬다.
            DispatchQueue.main.async { _ = panel }
        }
        if Self.animates {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.exitDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            finish()
        }
    }

    /// 시스템이 "동작 줄이기"를 켰으면 애니메이션을 끈다(접근성).
    private static var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static let enterDuration: Double = 0.14
    private static let exitDuration: Double = 0.10
    private static let enterSlide: CGFloat = 6

    private func resize(to size: NSSize) {
        guard let panel, panel.frame.size != size else { return }
        panel.setContentSize(size)
        reposition() // 크기가 바뀌면 앵커 기준이 어긋난다 — 자리도 다시 잡는다.
    }

    private func reposition() {
        guard let panel else { return }
        panel.setFrameOrigin(Self.origin(size: panel.frame.size, placement: placement))
    }

    /// 바깥 클릭·Esc·앱 비활성화를 감시한다. 판 안 클릭은 판 자신이 처리하므로 통과시킨다.
    private func installMonitors(for panel: NSPanel) {
        // 바깥 클릭은 닫는 데만 쓰고 아래로 흘리지 않는다(시스템 메뉴와 같은 동작) —
        // 닫으려던 클릭이 밑의 버튼까지 누르면 안 된다.
        let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // 그림자 여백(투명)에 떨어진 클릭도 "바깥"이다 — 눈에 보이는 판만이 판이다.
            let inside = event.window === panel
                && panel.frame.insetBy(dx: Elevation.margin, dy: Elevation.margin)
                    .contains(NSEvent.mouseLocation)
            guard !inside else { return event }
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

    /// 창 origin — 창은 콘텐츠보다 그림자 여백만큼 크므로, **콘텐츠** 위치를 먼저 정하고 여백만큼 물린다.
    private static func origin(size: NSSize, placement: PanelPlacement) -> NSPoint {
        let margin = Elevation.margin
        let content = NSSize(width: size.width - margin * 2, height: size.height - margin * 2)
        let anchor: NSPoint
        var x: CGFloat
        var y: CGFloat

        switch placement {
        case .menu(let point):
            anchor = point
            x = point.x
            y = point.y - content.height // 스크린 좌표는 좌하단 원점 — 아래로 펼치면 origin이 내려간다
        case .above(let rect):
            anchor = NSPoint(x: rect.midX, y: rect.midY)
            x = rect.midX - content.width / 2
            y = rect.maxY + Elevation.anchorGap
        }

        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSPoint(x: x - margin, y: y - margin) }

        switch placement {
        case .menu(let point):
            if x + content.width > visible.maxX { x = point.x - content.width } // 오른쪽 넘침 → 왼쪽으로
            if y < visible.minY { y = point.y }                                 // 아래 넘침 → 위로
        case .above(let rect):
            if y + content.height > visible.maxY { y = rect.minY - Elevation.anchorGap - content.height } // 위가 좁으면 아래로
        }
        x = min(max(x, visible.minX), max(visible.maxX - content.width, visible.minX))
        y = min(max(y, visible.minY), max(visible.maxY - content.height, visible.minY))
        return NSPoint(x: x - margin, y: y - margin)
    }
}

/// borderless 패널은 기본적으로 key가 되지 못한다 — hover·Esc를 받으려면 key가 돼야 한다.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 판의 SwiftUI 호스트. 두 가지를 더 한다:
/// 1. **첫 클릭 수용** — 비활성 창의 첫 클릭이 "창 활성화"에 먹히지 않게(한 번의 클릭으로 선택돼야 한다).
/// 2. **이상 크기 보고** — 내용이 자라면 창이 따라 커지도록 알린다.
private final class PanelHostingView: NSHostingView<AnyView> {
    var onIdealSizeChange: ((NSSize) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let ideal = fittingSize
        // 오차 허용치 없이 비교하면 부동소수 반올림으로 layout↔resize가 무한히 왕복할 수 있다.
        guard abs(ideal.width - frame.width) > 0.5 || abs(ideal.height - frame.height) > 0.5 else { return }
        onIdealSizeChange?(ideal)
    }

    @MainActor @preconcurrency required init(rootView: AnyView) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 미지원") }
}
