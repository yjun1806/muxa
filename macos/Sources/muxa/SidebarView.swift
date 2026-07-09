import AppKit

/// 좌측 워크스페이스 사이드바. (src/Sidebar.tsx 이식)
/// 표시 모드 4종: expanded(아바타+이름) / icon(아바타만) / slim(얇은 바) / hover(평소 아이콘).
/// hover는 M1에서 icon과 동일하게 취급한다(오버레이 펼침은 폴리시 단계).
final class SidebarView: NSView {
    var onSelect: ((String) -> Void)?

    private let stack = NSStackView()
    private var mode: SidebarMode = .expanded

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        addSubview(stack)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        stack.frame = bounds
    }

    /// 모드별 폭 — RootView가 레이아웃에 사용한다.
    var preferredWidth: CGFloat {
        switch mode {
        case .expanded, .hover: return 200
        case .icon: return 52
        case .slim: return 16
        }
    }

    func update(workspaces: [Workspace], activeId: String, mode: SidebarMode) {
        self.mode = mode
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, ws) in workspaces.enumerated() {
            stack.addArrangedSubview(makeItem(ws, index: i, active: ws.id == activeId))
        }
        needsLayout = true
    }

    private func makeItem(_ ws: Workspace, index: Int, active: Bool) -> NSView {
        let button = NSButton()
        button.isBordered = false
        button.target = self
        button.action = #selector(selectItem(_:))
        button.identifier = NSUserInterfaceItemIdentifier(ws.id)
        button.toolTip = ws.path ?? ws.name
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
        button.contentTintColor = active ? .controlAccentColor : .labelColor

        let avatar = ws.name.first.map { String($0).uppercased() } ?? "?"
        switch mode {
        case .slim:
            button.title = ""
            button.widthAnchor.constraint(equalToConstant: 4).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        case .icon, .hover:
            button.title = avatar
            button.font = .systemFont(ofSize: 13, weight: .semibold)
        case .expanded:
            let badge = index < 8 ? "  ⌘\(index + 1)" : ""
            button.title = "\(avatar)  \(ws.name)\(badge)"
            button.alignment = .left
            button.font = .systemFont(ofSize: 12)
        }
        return button
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onSelect?(id)
    }
}
