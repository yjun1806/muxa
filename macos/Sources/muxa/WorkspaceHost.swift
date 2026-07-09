import AppKit
import Carbon.HIToolbox
import GhosttyKit
import Observation

/// AppKit 터미널 호스트. 모든 (워크스페이스, 탭)의 WorkspaceView를 살려 두고
/// 활성 워크스페이스의 활성 탭만 표시한다 — 전환·백그라운드에서도 서피스·PTY가 유지된다.
/// 트리 변경은 onTreeChange로 AppState에 저장하고, ⌘1-8·⌘T·⌘⇧W를 여기서 처리한다.
///
/// SwiftUI(NSViewRepresentable)에 임베드하지 않는다 — 분할 시 내부 레이아웃이 SwiftUI
/// 제약 패스를 재귀 무효화해 창이 크래시하기 때문. RootView가 형제 뷰로 얹고,
/// 상태 변경은 observeAndSync()가 @Observable을 직접 관찰해 sync()를 다시 돌린다.
final class WorkspaceHostView: NSView {
    private let app: ghostty_app_t
    private let state: AppState
    private var views: [String: WorkspaceView] = [:] // key: tabId

    init(app: ghostty_app_t, state: AppState) {
        self.app = app
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    // 시스템 배경색을 여기서 칠한다 — 외관 변경 시 AppKit이 자동 재호출해 라이트/다크로 따라온다.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        layoutActive()
    }

    /// @Observable 상태(workspaces·activeId·activeTab)를 직접 관찰해 변할 때마다 sync를 다시 돈다.
    /// SwiftUI 밖 AppKit 뷰라 자동 갱신이 없으므로 withObservationTracking으로 대신한다.
    /// (SwiftUI에 임베드하면 분할 레이아웃이 제약 패스를 재귀 무효화해 크래시하기 때문에 분리했다.)
    func observeAndSync() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            // onChange는 변경 "직전"에 한 번 불린다 — 다음 런루프에서 재구독하며 sync를 다시 돈다.
            DispatchQueue.main.async { self?.observeAndSync() }
        }
    }

    /// 탭 뷰 생성/제거 + 활성만 표시 + 활성 패인 포커스.
    func sync() {
        let allTabIds = Set(state.workspaces.flatMap { $0.tabs.map(\.id) })
        for (id, view) in views where !allTabIds.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
        }
        for ws in state.workspaces {
            for tab in ws.tabs {
                let view = views[tab.id] ?? make(ws: ws, tab: tab)
                let isActive = ws.id == state.activeId && tab.id == ws.activeTabId
                view.isHidden = !isActive
            }
        }
        layoutActive()
        // 리포커스는 활성 탭이 실제로 바뀐 경우에만 — 트리 변경(분할/드래그)마다 하면 포커스가 튄다.
        let active = activeTabId
        if active != lastFocusedTabId {
            lastFocusedTabId = active
            if let activeView = views[active] {
                window?.makeFirstResponder(nil)
                activeView.focusActivePane()
            }
        }
    }

    private var lastFocusedTabId: String?

    private var activeTabId: String {
        state.activeWorkspace?.activeTabId ?? ""
    }

    private func make(ws: Workspace, tab: TermTab) -> WorkspaceView {
        let wsId = ws.id
        let tabId = tab.id
        let view = WorkspaceView(app: app, tab: tab, cwd: ws.path) { [weak self] tree, focusedId in
            self?.state.updateTab(wsId: wsId, tabId: tabId, tree: tree, focusedId: focusedId)
        }
        views[tab.id] = view
        addSubview(view)
        return view
    }

    private func layoutActive() {
        for view in views.values where !view.isHidden {
            if view.frame != bounds { view.frame = bounds } // 같은 값 재설정 방지(제약 루프)
        }
    }

    // MARK: 키바인딩 — ⌘1-8 전환 / ⌘T 새 탭 / ⌘⇧W 탭 닫기
    // WorkspaceView(하위)가 ⌘D/⌘W 등을 먼저 처리(super)하고, 남은 것을 여기서 받는다.

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.contains(.command) else { return false }

        if let s = event.charactersIgnoringModifiers, let n = Int(s),
           n >= 1, n <= 8, state.workspaces.indices.contains(n - 1) {
            state.setActiveId(state.workspaces[n - 1].id)
            return true
        }
        guard let wsId = state.activeWorkspace?.id else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_T:
            state.addTab(wsId: wsId)
            return true
        case kVK_ANSI_W where event.modifierFlags.contains(.shift):
            if let tabId = state.activeWorkspace?.activeTabId {
                state.closeTab(wsId: wsId, tabId: tabId)
            }
            return true
        default:
            return false
        }
    }
}
