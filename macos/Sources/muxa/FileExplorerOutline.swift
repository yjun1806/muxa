import AppKit
import SwiftUI

/// 파일 익스플로러 트리 — NSOutlineView 기반(키보드 네비·컨텍스트 메뉴·성능 네이티브).
/// 순수 로직(FileTree·git 상태·아이콘)은 Swift로 두고 이 파일은 뷰 레이어만 담당한다(cmux 구조 참고).
struct FileExplorerOutline: NSViewRepresentable {
    let root: String
    let reloadToken: Int
    let gitStatus: GitStatusMap
    var onOpenFile: (String) -> Void
    var onOpenTerminal: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outline = MuxaOutlineView()
        outline.headerView = nil
        outline.backgroundColor = Palette.bg
        outline.indentationPerLevel = 14
        outline.rowHeight = 22
        outline.usesAlternatingRowBackgroundColors = false
        outline.selectionHighlightStyle = .regular
        outline.allowsMultipleSelection = false
        outline.autoresizesOutlineColumn = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        let coordinator = context.coordinator
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.target = coordinator
        outline.onActivate = { [weak coordinator] node in coordinator?.activate(node) }
        outline.buildMenu = { [weak coordinator] node in coordinator?.makeMenu(for: node) }
        coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.bg

        coordinator.reload(root: root)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.props = self
        if coordinator.currentRoot != root {
            coordinator.reload(root: root)
        } else if coordinator.lastToken != reloadToken {
            coordinator.lastToken = reloadToken
            coordinator.reload(root: root) // 새로고침 — 구조를 캐시 무효화 후 재로드
        } else {
            // git 상태 등 갱신 — 펼침 상태를 유지한 채 셀 색만 다시 그린다.
            coordinator.outline?.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(props: self) }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var props: FileExplorerOutline
        weak var outline: NSOutlineView?
        var currentRoot = ""
        var lastToken = 0
        private var rootChildren: [FileNode] = []

        init(props: FileExplorerOutline) { self.props = props }

        func reload(root: String) {
            currentRoot = root
            rootChildren = FileTree.children(of: root)
            outline?.reloadData()
        }

        /// 지연 로드 — 폴더 자식은 처음 펼칠 때만 디스크에서 읽어 노드에 캐시.
        private func children(of item: Any?) -> [FileNode] {
            guard let node = item as? FileNode else { return rootChildren }
            if node.children == nil { node.children = FileTree.children(of: node.path) }
            return node.children ?? []
        }

        func activate(_ node: FileNode) {
            guard let outline else { return }
            if node.isDirectory {
                if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
            } else {
                props.onOpenFile(node.path)
            }
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let node = sender.item(atRow: row) as? FileNode else { return }
            activate(node)
        }

        // MARK: DataSource

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }
        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }
        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isDirectory ?? false
        }

        // MARK: Delegate

        func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = (ov.makeView(withIdentifier: id, owner: self) as? FileCellView) ?? FileCellView(id: id)
            cell.configure(node: node, status: props.gitStatus.status(for: node.path))
            return cell
        }

        func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            FileRowView()
        }

        // MARK: 컨텍스트 메뉴

        func makeMenu(for node: FileNode) -> NSMenu {
            let dir = node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
            let menu = NSMenu()
            let entries: [(String, () -> Void)] = [
                ("여기에서 터미널 열기", { self.props.onOpenTerminal(dir) }),
                ("Finder에서 표시", { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }),
                ("경로 복사", {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.path, forType: .string)
                }),
            ]
            for (title, action) in entries {
                let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ClosureBox(action)
                menu.addItem(item)
            }
            return menu
        }

        @objc func menuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? ClosureBox)?.action()
        }
    }
}

/// 클로저를 NSMenuItem.representedObject에 담기 위한 박스.
private final class ClosureBox {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

/// Enter로 열기 + 우클릭 메뉴를 지원하는 NSOutlineView. ↑↓←→ 펼침/이동은 기본 동작.
final class MuxaOutlineView: NSOutlineView {
    var onActivate: ((FileNode) -> Void)?
    var buildMenu: ((FileNode) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            if selectedRow >= 0, let node = item(atRow: selectedRow) as? FileNode {
                onActivate?(node)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, let node = item(atRow: row) as? FileNode else { return nil }
        if selectedRow != row {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return buildMenu?(node)
    }
}

/// 트리 셀 — 파일 타입 아이콘 + 이름(git 상태색).
final class FileCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.font = .systemFont(ofSize: 12.5)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.drawsBackground = false
        nameField.isBordered = false
        addSubview(iconView)
        addSubview(nameField)
        imageView = iconView
        textField = nameField
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    func configure(node: FileNode, status: GitFileStatus?) {
        let img = FileIcon.image(for: node)
        img.size = NSSize(width: 16, height: 16)
        iconView.image = img
        iconView.contentTintColor = node.isDirectory ? Palette.muted : nil
        nameField.stringValue = node.name
        nameField.textColor = status?.color ?? Palette.fg
    }
}

/// 트리 행 — 라운드 선택 하이라이트(accent).
final class FileRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        Palette.borderFocus.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}
