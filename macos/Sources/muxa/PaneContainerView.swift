import AppKit

/// 패인 하나의 컨테이너 = 헤더(분할·닫기 버튼) + 터미널(TermView). (src/TerminalPane.tsx + PaneHeader.tsx 이식)
///
/// 웹처럼 각 패인이 자기 컨트롤을 가진다("패인 선택 → 분할" 단계 없음).
/// 포커스 시 청록 테두리로 활성 패인을 시각적으로 구분한다(웹 --border-focus).
final class PaneContainerView: NSView {
    let paneId: String
    let term: TermView
    private let header: PaneHeaderView

    private let headerHeight: CGFloat = 22

    var focused: Bool = false {
        didSet {
            layer?.borderColor = (focused ? Palette.borderFocus : Palette.border).cgColor
            term.isFocused = focused
        }
    }

    init(paneId: String, term: TermView, onSplit: @escaping (Dir) -> Void, onClose: @escaping () -> Void) {
        self.paneId = paneId
        self.term = term
        self.header = PaneHeaderView(onSplit: onSplit, onClose: onClose)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = Palette.bg.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor

        addSubview(header)
        addSubview(term)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true } // 좌상단 원점 — 헤더가 위

    override func layout() {
        super.layout()
        // 1px 테두리 안쪽에 헤더·터미널을 배치
        header.frame = NSRect(x: 1, y: 1, width: bounds.width - 2, height: headerHeight)
        term.frame = NSRect(
            x: 1,
            y: 1 + headerHeight,
            width: bounds.width - 2,
            height: bounds.height - headerHeight - 2
        )
    }
}
