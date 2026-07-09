import AppKit

/// 패인별 헤더 — 그 패인을 직접 분할(좌우/위아래)·닫는다. (src/PaneHeader.tsx 이식)
/// 웹 `.pane-header`: 22px 높이, panel 회색, 하단 경계선, 버튼은 우측 정렬.
/// frame 기반 레이아웃 — 오토레이아웃을 쓰면 frame 기반 부모와 섞여 제약 갱신 루프로 크래시한다.
final class PaneHeaderView: NSView {
    private let buttons: [IconButton]

    private let buttonWidth: CGFloat = 20
    private let buttonHeight: CGFloat = 18
    private let gap: CGFloat = 1
    private let inset: CGFloat = 3

    init(onSplit: @escaping (Dir) -> Void, onClose: @escaping () -> Void) {
        // 세로 분할(좌우) = 두 열 → square.split.2x1 / 가로 분할(위아래) = 두 행 → square.split.1x2
        let row = IconButton(symbol: "square.split.2x1", tip: "세로 분할 · 좌우 (⌘D)") { onSplit(.row) }
        let col = IconButton(symbol: "square.split.1x2", tip: "가로 분할 · 위아래 (⌘⇧D)") { onSplit(.col) }
        let close = IconButton(symbol: "xmark", tip: "패인 닫기 (⌘W)") { onClose() }
        buttons = [row, col, close]

        super.init(frame: .zero)
        wantsLayer = true
        buttons.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // 우측 정렬: close가 가장 오른쪽, 이어서 col, row.
        var x = bounds.width - inset - buttonWidth
        let y = (bounds.height - buttonHeight) / 2
        for button in buttons.reversed() {
            button.frame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
            x -= (buttonWidth + gap)
        }
    }

    // 배경·경계선을 draw에서 칠한다 — 외관 변경 시 AppKit이 자동 재드로해 색이 라이트/다크로 따라온다.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Palette.panel.setFill()
        bounds.fill()
        // 하단 1px 경계선 (isFlipped라 y = 최하단)
        Palette.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
