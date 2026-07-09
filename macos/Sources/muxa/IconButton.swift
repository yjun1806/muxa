import AppKit

/// 클로저로 동작하는 무테 아이콘 버튼 — 패인 헤더 등 AppKit 툴바에서 재사용한다.
/// 웹 `.tool-btn`(24×24, hover 시 배경/색 강조) 대응. 크기·색은 생성 시 지정.
final class IconButton: NSButton {
    private let handler: () -> Void
    private var hovering = false

    init(symbol: String, tip: String, size: CGFloat = 20, pointSize: CGFloat = 12, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)

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

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size - 2),
        ])

        // hover 시 배경/색 강조 (웹 .tool-btn:hover)
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        layer?.backgroundColor = Palette.btnHover.cgColor
        contentTintColor = Palette.mutedHover
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = Palette.muted
    }

    @objc private func fire() { handler() }
}
