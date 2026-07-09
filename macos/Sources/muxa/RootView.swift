import AppKit
import GhosttyKit

/// 앱 루트 — 상단바 + [사이드바 | 워크스페이스 콘텐츠]를 조율한다. (src/App.tsx 이식)
///
/// 워크스페이스별 WorkspaceView를 만들어 두고 활성만 표시(isHidden)한다 — 전환해도
/// 서피스·PTY가 살아 있다. AppState가 목록/활성/모드를 소유하고, 변경 시 onChange로 sync한다.
final class RootView: NSView {
    private let app: ghostty_app_t
    private let state: AppState
    private let home: String

    private let topBar = TopBarView()
    private let sidebar = SidebarView()
    private let content = NSView()
    private var wsViews: [String: WorkspaceView] = [:]

    init(app: ghostty_app_t, state: AppState, home: String) {
        self.app = app
        self.state = state
        self.home = home
        super.init(frame: .zero)

        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        addSubview(content)
        addSubview(sidebar)
        addSubview(topBar)

        wireCallbacks()
        state.onChange = { [weak self] in self?.sync() }
        sync()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    private func wireCallbacks() {
        sidebar.onSelect = { [weak self] id in self?.state.setActiveId(id) }
        topBar.onSetMode = { [weak self] mode in self?.state.setSidebarMode(mode) }
        topBar.onAddHome = { [weak self] in self?.state.addWorkspace(path: self?.home) }
        topBar.onPick = { [weak self] in self?.pickFolder() }
    }

    // MARK: 상태 → UI

    private func sync() {
        let active = state.activeWorkspace
        topBar.update(
            activeName: active?.name,
            activePath: displayPath(active?.path, home: home),
            mode: state.sidebarMode
        )
        sidebar.update(workspaces: state.workspaces, activeId: state.activeId, mode: state.sidebarMode)

        // 사라진 워크스페이스 뷰 제거, 없는 것 생성, 활성만 표시
        let ids = Set(state.workspaces.map { $0.id })
        for (id, view) in wsViews where !ids.contains(id) {
            view.removeFromSuperview()
            wsViews[id] = nil
        }
        for ws in state.workspaces {
            let view = wsViews[ws.id] ?? makeWorkspaceView(ws)
            view.isHidden = (ws.id != state.activeId)
        }

        needsLayout = true
        wsViews[state.activeId]?.focusActivePane()
    }

    private func makeWorkspaceView(_ ws: Workspace) -> WorkspaceView {
        let view = WorkspaceView(app: app, workspace: ws) { [weak self] tree, focusedId in
            self?.state.updateWorkspace(id: ws.id, tree: tree, focusedId: focusedId)
        }
        wsViews[ws.id] = view
        content.addSubview(view)
        return view
    }

    // MARK: 레이아웃

    override func layout() {
        super.layout()
        let h = TopBarView.height
        topBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
        let sw = sidebar.preferredWidth
        sidebar.frame = NSRect(x: 0, y: h, width: sw, height: bounds.height - h)
        content.frame = NSRect(x: sw, y: h, width: bounds.width - sw, height: bounds.height - h)
        for view in wsViews.values {
            view.frame = content.bounds
        }
    }

    // MARK: ⌘1-8 워크스페이스 전환 (숫자는 자판 언어와 무관)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let s = event.charactersIgnoringModifiers, let n = Int(s),
              n >= 1, n <= 8, state.workspaces.indices.contains(n - 1)
        else { return false }
        state.setActiveId(state.workspaces[n - 1].id)
        return true
    }

    // MARK: 폴더 선택

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: home)
        if panel.runModal() == .OK, let url = panel.url {
            state.addWorkspace(path: url.path)
        }
    }
}
