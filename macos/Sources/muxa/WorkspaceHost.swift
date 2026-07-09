import AppKit
import Carbon.HIToolbox
import GhosttyKit
import SwiftUI

/// SwiftUI에 임베드되는 터미널 호스트. 모든 (워크스페이스, 탭)의 WorkspaceView를 살려 두고
/// 활성 워크스페이스의 활성 탭만 표시한다 — 전환·백그라운드에서도 서피스·PTY가 유지된다.
/// 트리 변경은 onTreeChange로 AppState에 저장하고, ⌘1-8·⌘T·⌘⇧W를 여기서 처리한다.
struct WorkspaceHost: NSViewRepresentable {
    let app: ghostty_app_t
    let state: AppState

    func makeNSView(context: Context) -> WorkspaceHostView {
        WorkspaceHostView(app: app, state: state)
    }

    func updateNSView(_ nsView: WorkspaceHostView, context: Context) {
        // sync()는 프레임·first responder를 바꿔 SwiftUI 레이아웃을 재무효화한다.
        // 레이아웃 패스 중 동기 실행하면 "Update Constraints" 재귀 루프로 창이 크래시하므로
        // 다음 런루프로 미뤄 패스 밖에서 실행한다.
        DispatchQueue.main.async { [weak nsView] in nsView?.sync() }
    }
}

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

    /// SwiftUI 상태 변경 시 호출 — 탭 뷰 생성/제거, 활성만 표시.
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
        if let activeView = views[activeTabId] {
            window?.makeFirstResponder(nil)
            activeView.focusActivePane()
        }
    }

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
            view.frame = bounds
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
