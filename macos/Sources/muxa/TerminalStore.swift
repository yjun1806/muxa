import AppKit
import Bonsplit
import GhosttyKit
import Observation

/// Bonsplit 탭이 담는 내용 — 터미널이거나 뷰어(diff 등). B(뷰어)에서 md/code 추가 예정.
enum TabContent {
    case terminal
    case diff(GitDiffTarget)
    case file(FileViewTarget)
}

/// 워크스페이스 하나의 터미널 집합 + Bonsplit 분할·탭 컨트롤러. (cmux DockSplitStore 대응)
///
/// Bonsplit이 분할 트리·탭 레이아웃을 SwiftUI로 관리하고, 우리는 tabId마다 TermView 하나를
/// 만들어 매핑한다(패인 내용 = 그 tabId의 터미널). 수동 AppKit 레이아웃이 없어져
/// 제약 엔진 폭주(분할 크래시)가 원천 소멸한다.
@MainActor
@Observable
final class TerminalStore: NSObject, BonsplitDelegate {
    let controller: BonsplitController

    @ObservationIgnored private let app: ghostty_app_t
    @ObservationIgnored private let cwd: String?
    @ObservationIgnored private var terms: [TabID: TermView] = [:]
    /// 터미널이 아닌 탭(diff 등)의 내용. 없으면 .terminal.
    @ObservationIgnored private var tabContent: [TabID: TabContent] = [:]

    /// 백그라운드 활동(●)으로 배지가 붙은 탭들(A). 프로젝트 배지가 이걸 파생·관측한다.
    var badgedTabs: Set<TabID> = []
    /// 배지가 하나라도 생기면 상위(AppState)에 알린다 — 프로젝트 탭 ● 표시용.
    @ObservationIgnored var onProjectActivity: (() -> Void)?

    var hasBadge: Bool { !badgedTabs.isEmpty }

    /// 이 스토어(프로젝트)의 시작 폴더 — diff/뷰어 탭이 참조한다.
    var workingDir: String? { cwd }

    /// 최초 표시 시 복원할 저장된 분할 트리(없으면 초기 터미널 1개). ensureInitialTerminal에서 소비.
    @ObservationIgnored private var restoreTree: ExternalTreeNode?
    /// 복원 replay 중에는 delegate 부작용(자동 새 터미널 생성)을 막는다.
    @ObservationIgnored private var restoring = false

    init(app: ghostty_app_t, cwd: String?, restoreTree: ExternalTreeNode? = nil) {
        self.app = app
        self.cwd = cwd
        self.restoreTree = restoreTree
        self.controller = BonsplitController()
        super.init()
        controller.delegate = self
    }

    // MARK: BonsplitDelegate — 분할·새탭·닫기에 터미널 생명주기를 잇는다

    /// 분할 즉시 새 패인에 터미널을 만든다 — 빈 패인을 거치지 않는다(muxa 원래 동작).
    /// 복원 중엔 replay가 탭을 직접 채우므로 자동 생성을 건너뛴다.
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        if restoring { return }
        newTerminal(inPane: newPane)
    }

    /// 탭바 `+` 버튼 → 새 터미널.
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
        newTerminal(inPane: pane)
    }

    /// 탭이 닫히면 그 터미널(PTY·서피스)·뷰어 상태를 해제한다.
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {
        terms[tabId] = nil // TermView deinit이 서피스 free
        tabContent[tabId] = nil
        badgedTabs.remove(tabId)
    }

    /// 현재 포커스된 패인의 터미널(단축키 대상 — ⌘F 등). diff 등 비-터미널 탭이면 nil.
    var focusedTerm: TermView? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane),
              case .terminal = content(for: tab.id) else { return nil }
        return term(for: tab.id)
    }

    /// 탭의 내용 종류(터미널이거나 diff 등 뷰어).
    func content(for tabId: TabID) -> TabContent {
        tabContent[tabId] ?? .terminal
    }

    /// tabId에 대응하는 터미널 뷰(없으면 생성). 패인 내용 렌더에서 호출한다.
    func term(for tabId: TabID) -> TermView {
        if let t = terms[tabId] { return t }
        let t = TermView(app: app, cwd: cwd)
        t.tabId = tabId
        // 콜백은 action_cb(메인 async)·becomeFirstResponder(메인)에서만 불린다 → assumeIsolated 안전.
        t.onBadgeActivity = { [weak self] tid in MainActor.assumeIsolated { self?.markBadge(tid) } }
        t.onClearBadge = { [weak self] tid in MainActor.assumeIsolated { self?.clearTabBadge(tid) } }
        t.onNotify = { title, body in
            MainActor.assumeIsolated { NotificationService.shared.notify(title: title, body: body) }
        }
        terms[tabId] = t
        return t
    }

    /// 백그라운드 활동으로 이 탭에 배지(●)를 켠다 — 탭 점(Bonsplit isDirty) + 프로젝트 알림.
    private func markBadge(_ tabId: TabID) {
        badgedTabs.insert(tabId)
        controller.updateTab(tabId, isDirty: true)
        onProjectActivity?()
    }

    /// 사용자가 탭을 보면 배지를 끈다.
    func clearTabBadge(_ tabId: TabID) {
        guard badgedTabs.contains(tabId) else { return }
        badgedTabs.remove(tabId)
        controller.updateTab(tabId, isDirty: false)
    }

    /// 새 터미널 탭 생성(분할 후 빈 패인 채우기·⌘T 등).
    @discardableResult
    func newTerminal(inPane pane: PaneID? = nil) -> TabID? {
        controller.createTab(title: "터미널", icon: "terminal", inPane: pane)
    }

    /// diff를 현재 포커스 패인의 새 탭으로 연다(모달 아님). 같은 대상 탭이 있으면 그걸 선택.
    @discardableResult
    func openDiff(_ target: GitDiffTarget) -> TabID? {
        if let existing = tabContent.first(where: {
            if case .diff(let t) = $0.value { return t.id == target.id }
            return false
        })?.key {
            controller.selectTab(existing)
            return existing
        }
        guard let tabId = controller.createTab(title: target.tabTitle, icon: target.tabIcon, inPane: controller.focusedPaneId) else { return nil }
        tabContent[tabId] = .diff(target)
        controller.selectTab(tabId) // 새 diff 탭을 바로 앞으로
        return tabId
    }

    /// 파일을 현재 포커스 패인의 새 탭(뷰어)으로 연다. 같은 경로 탭이 있으면 그걸 선택.
    /// diff와 동일한 dedup→createTab 패턴. 종류(md/코드)는 렌더에서 FileViewTarget.kind로 분기.
    @discardableResult
    func openFile(_ path: String) -> TabID? {
        let target = FileViewTarget(path: path)
        if let existing = tabContent.first(where: {
            if case .file(let t) = $0.value { return t.id == target.id }
            return false
        })?.key {
            controller.selectTab(existing)
            return existing
        }
        guard let tabId = controller.createTab(title: target.tabTitle, icon: target.tabIcon, inPane: controller.focusedPaneId) else { return nil }
        tabContent[tabId] = .file(target)
        controller.selectTab(tabId)
        return tabId
    }

    /// 최초 표시 시: 저장된 트리가 있으면 복원, 없으면 초기 터미널 1개.
    func ensureInitialTerminal() {
        guard controller.allTabIds.isEmpty else { return }
        if let tree = restoreTree {
            restoreTree = nil
            restore(tree)
        } else {
            newTerminal()
        }
    }

    // MARK: 세션 레이아웃 복원 — 저장된 분할 트리를 replay로 재구성
    //
    // Bonsplit엔 복원 API가 없어(1.1.1) createTab/splitPane 재생으로 구조를 다시 만든다.
    // PTY는 프로세스라 복원 불가 → 각 탭은 워크스페이스 cwd에서 새 셸로 시작한다.
    // 트리를 저장본에서 만들므로 구조는 구성상 동일하고, divider는 lockstep으로 맞춘다.

    /// 저장 트리를 현재 컨트롤러에 재구성. 실패해도 안전 폴백(터미널 1개).
    private func restore(_ tree: ExternalTreeNode) {
        restoring = true
        realize(tree, into: controller.allPaneIds.first)
        restoring = false

        // 복원이 아무 탭도 못 만들었으면(예상 밖) 안전 폴백.
        if controller.allTabIds.isEmpty {
            newTerminal()
            return
        }
        applyDividers(saved: tree, current: controller.treeSnapshot())
    }

    /// 트리 노드를 targetPane에 실현한다. split은 먼저 쪼갠 뒤(빈 두 패인) 양쪽을 채운다.
    private func realize(_ node: ExternalTreeNode, into pane: PaneID?) {
        guard let pane else { return }
        switch node {
        case .pane(let paneNode):
            for _ in paneNode.tabs { newTerminal(inPane: pane) }
        case .split(let splitNode):
            let orientation: SplitOrientation = splitNode.orientation == "vertical" ? .vertical : .horizontal
            guard let newPane = controller.splitPane(pane, orientation: orientation, withTab: nil) else {
                // 분할 실패 시 서브트리를 현재 패인에 평면화(구조는 잃어도 탭은 산다).
                realize(splitNode.first, into: pane)
                realize(splitNode.second, into: pane)
                return
            }
            realize(splitNode.first, into: pane) // 기존 패인 = split의 first
            realize(splitNode.second, into: newPane) // 새 패인 = second
        }
    }

    /// saved·current 트리는 구조가 동일하므로 lockstep으로 divider 비율을 복원한다(best-effort).
    private func applyDividers(saved: ExternalTreeNode, current: ExternalTreeNode) {
        guard case .split(let s) = saved, case .split(let c) = current else { return }
        if let uuid = UUID(uuidString: c.id) {
            _ = controller.setDividerPosition(CGFloat(s.dividerPosition), forSplit: uuid, fromExternal: true)
        }
        applyDividers(saved: s.first, current: c.first)
        applyDividers(saved: s.second, current: c.second)
    }
}
