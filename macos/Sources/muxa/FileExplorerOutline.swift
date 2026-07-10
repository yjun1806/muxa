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
        /// 펼쳐진 폴더 경로 — reload(노드 재생성)에도 펼침 상태를 유지하려 경로로 추적한다.
        private var expandedPaths: Set<String> = []

        init(props: FileExplorerOutline) { self.props = props }

        func reload(root: String) {
            currentRoot = root
            rootChildren = FileTree.children(of: root) // 새 노드 → 캐시 무효화
            outline?.reloadData()
            restoreExpansion() // 펼침 상태 복원(경로 기준)
        }

        /// expandedPaths에 있는 폴더를 깊이 우선으로 다시 펼친다(조상부터 lazy 로드).
        private func restoreExpansion() {
            guard let outline else { return }
            func walk(_ nodes: [FileNode]) {
                for n in nodes where n.isDirectory && expandedPaths.contains(n.path) {
                    outline.expandItem(n)
                    walk(n.children ?? [])
                }
            }
            walk(rootChildren)
        }

        func outlineViewItemDidExpand(_ n: Notification) {
            if let node = n.userInfo?["NSObject"] as? FileNode { expandedPaths.insert(node.path) }
        }
        func outlineViewItemDidCollapse(_ n: Notification) {
            if let node = n.userInfo?["NSObject"] as? FileNode { expandedPaths.remove(node.path) }
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
            let row = FileRowView()
            row.indentLevel = ov.level(forRow: ov.row(forItem: item))
            row.indentPerLevel = ov.indentationPerLevel
            return row
        }

        // MARK: 컨텍스트 메뉴

        func makeMenu(for node: FileNode) -> NSMenu {
            let dir = node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
            let menu = NSMenu()
            var entries: [(String, () -> Void)] = [
                ("새 파일…", { self.createEntry(in: dir, directory: false) }),
                ("새 폴더…", { self.createEntry(in: dir, directory: true) }),
            ]
            entries.append(("__sep__", {}))
            entries.append(contentsOf: [
                ("이름 변경…", { self.rename(node) }),
                ("삭제", { self.delete(node) }),
                ("__sep__", {}),
                ("여기에서 터미널 열기", { self.props.onOpenTerminal(dir) }),
                ("Finder에서 표시", { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }),
                ("경로 복사", {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.path, forType: .string)
                }),
            ])
            for (title, action) in entries {
                if title == "__sep__" { menu.addItem(.separator()); continue }
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

        // MARK: 파일 조작 (새로 만들기·이름 변경·삭제)

        /// dir 안에 새 파일/폴더를 만든다. 이름 입력 후 생성 → 트리 갱신 + 그 폴더 펼침.
        private func createEntry(in dir: String, directory: Bool) {
            guard let name = promptText(title: directory ? "새 폴더 이름" : "새 파일 이름", initial: ""),
                  !name.isEmpty else { return }
            let path = (dir as NSString).appendingPathComponent(name)
            let fm = FileManager.default
            do {
                if directory {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: false)
                } else {
                    guard fm.createFile(atPath: path, contents: Data()) else { throw CocoaError(.fileWriteUnknown) }
                }
                expandedPaths.insert(dir) // 새 항목이 보이도록 대상 폴더 펼침
                reload(root: currentRoot)
                if !directory { props.onOpenFile(path) } // 새 파일은 바로 연다
            } catch {
                warn("만들 수 없습니다: \(name)")
            }
        }

        /// 파일/폴더 이름 변경(moveItem).
        private func rename(_ node: FileNode) {
            let old = node.name
            guard let name = promptText(title: "이름 변경", initial: old), !name.isEmpty, name != old else { return }
            let dst = ((node.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(atPath: node.path, toPath: dst)
                reload(root: currentRoot)
            } catch {
                warn("이름을 바꿀 수 없습니다: \(name)")
            }
        }

        /// 파일/폴더 삭제 — 휴지통으로(복구 가능). 확인 후.
        private func delete(_ node: FileNode) {
            let alert = NSAlert()
            alert.messageText = "'\(node.name)'을(를) 휴지통으로 보낼까요?"
            alert.informativeText = node.isDirectory ? "폴더와 내용이 함께 이동됩니다." : ""
            alert.alertStyle = .warning
            alert.addButton(withTitle: "휴지통으로")
            alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            NSWorkspace.shared.recycle([URL(fileURLWithPath: node.path)]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reload(root: self?.currentRoot ?? "") }
            }
        }

        /// 텍스트 입력 시트(간단). 확인 시 트림한 값, 취소 시 nil.
        private func promptText(title: String, initial: String) -> String? {
            let alert = NSAlert()
            alert.messageText = title
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = initial
            alert.accessoryView = field
            alert.addButton(withTitle: "확인")
            alert.addButton(withTitle: "취소")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            return field.stringValue.trimmingCharacters(in: .whitespaces)
        }

        private func warn(_ text: String) {
            let alert = NSAlert()
            alert.messageText = text
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
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
        // 컬러 아이콘(Material)은 원색 유지, 템플릿(SF 폴백)만 muted 틴트.
        iconView.contentTintColor = img.isTemplate ? Palette.muted : nil
        nameField.stringValue = node.name
        nameField.textColor = status?.color ?? Palette.fg
    }
}

/// 트리 행 — 라운드 선택 하이라이트(accent) + 인덴트 가이드(VSCode식 세로 안내선).
final class FileRowView: NSTableRowView {
    var indentLevel = 0
    var indentPerLevel: CGFloat = 16

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard indentLevel > 0 else { return }
        Palette.border.withAlphaComponent(0.6).setStroke()
        // 각 조상 레벨마다 세로선 하나. 디스클로저 삼각형 열 중앙쯤에 맞춘다.
        for i in 1...indentLevel {
            let x = (CGFloat(i) - 0.5) * indentPerLevel + 8
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: NSPoint(x: x, y: 0))
            line.line(to: NSPoint(x: x, y: bounds.height))
            line.stroke()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        Palette.borderFocus.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}
