import AppKit

/// 전체 폭 상단바. (src/TopBar.tsx + SidebarControls.tsx 이식)
/// 좌측에 신호등 여백 + 사이드바 컨트롤(모드·추가), 가운데 활성 워크스페이스 이름/경로.
/// 팝오버는 AppKit NSMenu로 대체한다(hover 팝오버 → 버튼 클릭 메뉴).
final class TopBarView: NSView {
    static let height: CGFloat = 28
    private let trafficLightInset: CGFloat = 72 // 신호등 영역

    var onSetMode: ((SidebarMode) -> Void)?
    var onAddHome: (() -> Void)?
    var onPick: (() -> Void)?

    private let modeButton = NSButton()
    private let addButton = NSButton()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private var currentMode: SidebarMode = .expanded

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        configureToolButton(modeButton, symbol: "sidebar.left", action: #selector(showModeMenu))
        configureToolButton(addButton, symbol: "plus", action: #selector(showAddMenu))

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor

        [modeButton, addButton, nameLabel, pathLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    private func configureToolButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
    }

    override func layout() {
        super.layout()
        let y: CGFloat = 2
        let size: CGFloat = 24
        modeButton.frame = NSRect(x: trafficLightInset, y: y, width: size, height: size)
        addButton.frame = NSRect(x: trafficLightInset + size + 4, y: y, width: size, height: size)
        let textX = trafficLightInset + 2 * size + 16
        nameLabel.sizeToFit()
        nameLabel.frame = NSRect(x: textX, y: 6, width: nameLabel.frame.width, height: 16)
        pathLabel.sizeToFit()
        pathLabel.frame = NSRect(
            x: textX + nameLabel.frame.width + 8, y: 7,
            width: min(pathLabel.frame.width, bounds.width - textX - nameLabel.frame.width - 20),
            height: 14
        )
    }

    func update(activeName: String?, activePath: String, mode: SidebarMode) {
        currentMode = mode
        nameLabel.stringValue = activeName ?? ""
        pathLabel.stringValue = activePath
        needsLayout = true
    }

    // MARK: 메뉴

    @objc private func showModeMenu() {
        let menu = NSMenu()
        for m in SidebarMode.allCases {
            let item = NSMenuItem(title: "\(m.label) — \(m.hint)", action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = (m == currentMode) ? .on : .off
            menu.addItem(item)
        }
        popUp(menu, from: modeButton)
    }

    @objc private func showAddMenu() {
        let menu = NSMenu()
        let home = NSMenuItem(title: "홈에서 열기", action: #selector(pickHome), keyEquivalent: "")
        let pick = NSMenuItem(title: "폴더 선택…", action: #selector(pickFolder), keyEquivalent: "")
        [home, pick].forEach { $0.target = self; menu.addItem($0) }
        popUp(menu, from: addButton)
    }

    private func popUp(_ menu: NSMenu, from button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = SidebarMode(rawValue: raw) else { return }
        onSetMode?(mode)
    }

    @objc private func pickHome() { onAddHome?() }
    @objc private func pickFolder() { onPick?() }
}
