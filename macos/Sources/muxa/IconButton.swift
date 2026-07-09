import AppKit

/// 클로저로 동작하는 무테 아이콘 버튼 — 패인 헤더 등 AppKit 툴바에서 재사용한다.
/// 웹 `.tool-btn`(hover 시 배경/색 강조) 대응. frame 기반 레이아웃(부모가 frame을 지정).
/// 오토레이아웃 제약을 쓰지 않는다 — frame 기반 부모(WorkspaceView 계열)와 섞이면
/// 제약 갱신 무한 루프로 창이 크래시한다.
final class IconButton: NSButton {
    private let handler: () -> Void

    init(symbol: String, tip: String, pointSize: CGFloat = 12, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false // 수동 프레임 — 제약 엔진 제외

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config)
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        toolTip = tip
        contentTintColor = Palette.muted
        wantsLayer = true
        layer?.cornerRadius = 5
        target = self
        action = #selector(fire)

        // hover 시 배경/색 강조 (웹 .tool-btn:hover). inVisibleRect라 frame이 바뀌어도 자동 추적.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Palette.btnHover.cgColor
        contentTintColor = Palette.mutedHover
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = Palette.muted
    }

    @objc private func fire() { handler() }
}
