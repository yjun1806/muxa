import AppKit

/// 패인별 헤더 — 그 패인을 직접 분할(좌우/위아래)·닫는다. (src/PaneHeader.tsx 이식)
/// 웹 `.pane-header`: 22px 높이, panel 회색, 하단 경계선, 버튼은 우측 정렬.
final class PaneHeaderView: NSView {
    init(onSplit: @escaping (Dir) -> Void, onClose: @escaping () -> Void) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = Palette.panel.cgColor

        // 하단 경계선
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = Palette.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // 세로 분할(좌우) = 두 열 → square.split.2x1 / 가로 분할(위아래) = 두 행 → square.split.1x2
        let row = IconButton(symbol: "square.split.2x1", tip: "세로 분할 · 좌우 (⌘D)") { onSplit(.row) }
        let col = IconButton(symbol: "square.split.1x2", tip: "가로 분할 · 위아래 (⌘⇧D)") { onSplit(.col) }
        let close = IconButton(symbol: "xmark", tip: "패인 닫기 (⌘W)") { onClose() }

        let stack = NSStackView(views: [row, col, close])
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }
}
