import AppKit
import SwiftUI

/// muxa 팝오버 툴팁 — NSToolTip 대체 컴포넌트.
///
/// NSToolTip은 지연을 **앱 전역으로만**(`NSInitialToolTipDelay`) 조절할 수 있어, 탭바의 아이콘 전용
/// 버튼(분할·새 터미널) 하나 때문에 앱의 모든 툴팁이 즉시 뜨는 해킹을 깔아야 했다 — 그게 더 거슬렸다.
/// 이 컴포넌트는 지연·모양·위치를 앱이 소유한다: hover 후 `Tip.delay` 뒤에 앵커 아래로
/// **칩**(SidebarNameChip과 같은 표면 문법)이 뜨고, 벗어나거나 클릭·키 입력이 오면 사라진다.
///
/// Bonsplit 탭바(스플릿 버튼·탭 제목·오디오 배지)는 `BonsplitTooltipHost.render`를 통해
/// 이걸 쓴다(`main.swift`에서 주입). muxa 자체 뷰도 `.muxaTip(_:)`으로 쓸 수 있다.
enum Tip {
    /// hover → 표시까지의 지연. 시스템 기본(~1s+)보다 빠르되 스치기만 해도 뜨진 않게.
    static let delay: TimeInterval = 0.5
}

extension View {
    /// 이 뷰에 muxa 팝오버 툴팁을 단다. nil/빈 문자열이면 아무것도 안 단다.
    func muxaTip(_ text: String?) -> some View {
        background(TipAnchor(text: text).allowsHitTesting(false))
    }

    /// 이 뷰에 **hover 카드**를 단다 — 한 줄 칩 대신 임의 콘텐츠(잘린 전문·이미지 미리보기).
    /// 표시 규칙(지연·이탈·클릭 시 접기)은 툴팁과 동일하다. `key`가 바뀌면 떠 있던 카드를 접는다
    /// (행 재사용·내용 교체 대응 — 클로저는 비교할 수 없어 키가 동일성을 대신 말한다).
    func muxaHoverCard(key: String, @ViewBuilder content: @escaping () -> some View) -> some View {
        background(HoverCardAnchor(key: key, content: { AnyView(content()) }).allowsHitTesting(false))
    }
}

// MARK: - 칩 (표면)

/// 툴팁 칩 — `SidebarNameChip`과 같은 표면 문법(panel + border + key 그림자)의 한 줄 caption판.
/// 이름 칩과 합치지 않는 이유: 저긴 "정체성(제목+경로)", 여긴 "설명 한 줄" — 내용 구조가 다르다.
private struct TipChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.muxa(.caption))
            .foregroundStyle(Color.pFg)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.tight)
            .background(Color.pPanel)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
            .shadow(color: .black.opacity(Elevation.keyOpacity),
                    radius: Elevation.keyRadius, y: Elevation.keyOffsetY)
            .padding(Elevation.margin) // 그림자가 창 경계에서 직각으로 잘리지 않을 자리(FloatingPanel과 같은 사정)
    }
}

// MARK: - 앵커 (hover 추적)

private struct TipAnchor: NSViewRepresentable {
    let text: String?

    func makeNSView(context: Context) -> TipHostView {
        let view = TipHostView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: TipHostView, context: Context) {
        apply(to: nsView)
    }

    static func dismantleNSView(_ nsView: TipHostView, coordinator: ()) {
        nsView.cancel()
    }

    private func apply(to view: TipHostView) {
        view.contentKey = normalized
        view.provider = normalized.map { text in { AnyView(TipChip(text: text)) } }
    }

    private var normalized: String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// 리치 카드 앵커 — 칩(TipChip) 대신 호출자가 준 콘텐츠를 띄운다. hover 규칙은 TipHostView 공용.
private struct HoverCardAnchor: NSViewRepresentable {
    let key: String
    let content: () -> AnyView

    func makeNSView(context: Context) -> TipHostView {
        let view = TipHostView()
        view.contentKey = key
        view.provider = content
        return view
    }

    func updateNSView(_ nsView: TipHostView, context: Context) {
        nsView.contentKey = key
        nsView.provider = content
    }

    static func dismantleNSView(_ nsView: TipHostView, coordinator: ()) {
        nsView.cancel()
    }
}

/// 앵커 뷰 — hover 진입에서 지연 타이머를 걸고, 이탈·창 분리에서 접는다(칩·카드 공용).
/// 히트테스트는 없다(클릭은 아래 컨트롤이 받는다) — 트래킹 영역은 히트테스트와 무관하게 동작한다.
private final class TipHostView: NSView {
    /// 띄울 내용 공급자 — nil이면 아무것도 안 띄운다(표시 순간에 만든다 — 안 뜰 카드를 미리 만들지 않는다).
    var provider: (() -> AnyView)?
    /// 내용 동일성 키 — 클로저는 비교할 수 없어 이 키가 "내용이 바뀌었다"를 대신 말한다(바뀌면 접는다).
    var contentKey: String? {
        didSet { if contentKey != oldValue { cancel() } }
    }

    private var pending: DispatchWorkItem?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard provider != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.present() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Tip.delay, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancel() }
    }

    /// 대기 중인 표시를 취소하고, 떠 있으면 접는다.
    func cancel() {
        pending?.cancel()
        pending = nil
        TipWindow.shared.hide()
    }

    private func present() {
        guard let window, let provider else { return }
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        TipWindow.shared.show(view: provider(), anchor: anchor)
    }

    deinit {
        pending?.cancel()
    }
}

// MARK: - 창

/// 툴팁 칩 하나를 띄우는 공용 창 — 한 번에 하나만 뜬다(새로 뜨면 이전 것이 접힌다).
///
/// `FloatingPanelHost`(메뉴·팝오버)를 안 쓰는 이유: 저긴 **상호작용하는 판**이라 바깥클릭 모니터·
/// 포커스 복원을 소유한다. 툴팁은 정반대다 — 마우스를 완전히 무시하고, 포커스를 절대 건드리지 않는다.
@MainActor
final class TipWindow {
    static let shared = TipWindow()
    private var panel: NSPanel?
    /// 떠 있는 동안 클릭·스크롤·키 입력이 오면 접는 모니터 — 툴팁이 상호작용 위에 남아 있지 않게.
    private var monitor: Any?

    func show(text: String, anchor: NSRect) {
        show(view: AnyView(TipChip(text: text)), anchor: anchor)
    }

    /// 임의 콘텐츠(리치 카드)를 띄운다 — 칩과 같은 창 규칙(마우스 무시·포커스 불가침).
    /// 콘텐츠는 **표시 시점 크기로 고정**된다 — 비동기 로드가 있으면 자리(placeholder)를 먼저 잡아야 한다.
    func show(view: AnyView, anchor: NSRect) {
        hide()
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // 그림자는 칩(SwiftUI)이 그린다 — 창 그림자는 여백 사각형을 따라가 어긋난다
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.setFrameOrigin(origin(chipSize: size, anchor: anchor))
        panel.orderFront(nil)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            self?.hide()
            return event
        }
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// 칩(그림자 여백 포함)의 창 원점 — 앵커 아래 가로 중앙, 화면을 벗어나면 클램프하고 아래가 좁으면 위로.
    /// 여백(`Elevation.margin`)은 시각 위치 계산에서 상쇄한다 — 칩 **본체**가 앵커에서 `anchorGap`만큼 떨어진다.
    private func origin(chipSize: NSSize, anchor: NSRect) -> NSPoint {
        let margin = Elevation.margin
        var x = anchor.midX - chipSize.width / 2
        var y = anchor.minY - Elevation.anchorGap - chipSize.height + margin // 아래에(본체 기준)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX - margin), visible.maxX - chipSize.width + margin)
            if y + margin < visible.minY { // 아래 공간 부족 → 앵커 위로 뒤집기
                y = anchor.maxY + Elevation.anchorGap - margin
            }
        }
        return NSPoint(x: x, y: y)
    }
}
