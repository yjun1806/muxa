import AppKit
import Bonsplit
import GhosttyKit
import Observation

/// Bonsplit 탭이 담는 내용 — 터미널(개별 탭)이거나 그룹 탭(문서·diff 묶음).
/// 문서/diff는 종류별로 그룹 탭 하나에 서브탭으로 모인다(2단 탭). 상태는 `groups`가 소유.
enum TabContent {
    case terminal
    case group(TabGroupKind)
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
    /// 터미널이 아닌 탭의 종류(그룹). 없으면 .terminal.
    @ObservationIgnored private var tabContent: [TabID: TabContent] = [:]
    /// 그룹 탭(TabID) → 서브탭 상태(문서·diff 묶음). TabGroupView가 관측한다.
    @ObservationIgnored private var groups: [TabID: TabGroupState] = [:]

    /// 백그라운드 활동(●)으로 배지가 붙은 탭들(A). 프로젝트 배지가 이걸 파생·관측한다.
    var badgedTabs: Set<TabID> = []
    /// 배지가 하나라도 생기면 상위(AppState)에 알린다 — 프로젝트 탭 ● 표시용.
    @ObservationIgnored var onProjectActivity: (() -> Void)?

    var hasBadge: Bool { !badgedTabs.isEmpty }

    /// 이 스토어(프로젝트)의 시작 폴더 — diff/뷰어 탭이 참조한다.
    var workingDir: String? { cwd }

    /// 최초 표시 시 복원할 저장된 분할 트리(없으면 초기 터미널 1개). ensureInitialTerminal에서 소비.
    @ObservationIgnored private var restoreTree: ExternalTreeNode?
    /// 재시작 시 다시 열 문서/커밋 diff(터미널 복원 후 재오픈). ensureInitialTerminal에서 소비.
    @ObservationIgnored private var restoreViewers: [SavedViewer]
    /// 복원 replay 중에는 delegate 부작용(자동 새 터미널 생성)을 막는다.
    @ObservationIgnored private var restoring = false
    /// ensureInitialTerminal 1회 보장 — Bonsplit이 초기 "Welcome" 탭을 넣어 allTabIds가 비지 않으므로 플래그로 판별.
    @ObservationIgnored private var initialized = false

    init(app: ghostty_app_t, cwd: String?, restoreTree: ExternalTreeNode? = nil, restoreViewers: [SavedViewer] = []) {
        self.app = app
        self.cwd = cwd
        self.restoreTree = restoreTree
        self.restoreViewers = restoreViewers
        // keepAllAlive — 탭 전환 시 뷰(WKWebView 뷰어·터미널)를 파괴/재생성하지 않고 유지한다.
        // 기본 .recreateOnSwitch는 전환마다 뷰어를 재로드(굼뜸·상태 손실)해서 부적합.
        var config = BonsplitConfiguration(contentViewLifecycle: .keepAllAlive)
        // 탭바 내장 액션 버튼: [새 터미널(+), 우측 분할, 하단 분할]. 브라우저는 muxa에 없어 제외.
        // .newTerminal → requestNewTab(kind:"terminal") → didRequestNewTab 델리게이트 → newTerminal().
        config.appearance.splitButtons = [.newTerminal, .splitRight, .splitDown]
        self.controller = BonsplitController(configuration: config)
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
        groups[tabId] = nil // 그룹 탭이면 서브탭 상태도 해제
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
        let id = controller.createTab(title: "터미널", icon: "terminal", inPane: pane)
        if let id { regroup(id, inPane: pane ?? controller.focusedPaneId) }
        return id
    }

    // MARK: 탭 그룹핑 — 같은 종류끼리 묶기 (터미널 | 문서 | diff)
    //
    // 탭바에서 "문서는 문서끼리, diff는 diff끼리" 인접하도록 종류별 rank로 정렬 위치를 잡는다.
    // 복원 중엔 저장된 순서를 존중하므로 건너뛴다.

    /// 탭 종류 정렬 순위 — 터미널(0) < 문서(1) < diff(2). 같은 순위는 생성 순서 유지.
    private func groupRank(_ content: TabContent) -> Int {
        switch content {
        case .terminal: return 0
        case .group(.documents): return 1
        case .group(.diffs): return 2
        }
    }

    /// 방금 만든 탭을 같은 종류 묶음의 끝(다음 순위 묶음 앞)으로 이동해 클러스터를 유지한다.
    private func regroup(_ tabId: TabID, inPane pane: PaneID?) {
        guard !restoring, let pane else { return }
        let rank = groupRank(content(for: tabId))
        // 자기 자신을 뺀 나머지 중 순위 ≤ 내 순위인 탭 수 = 삽입 위치(내 묶음의 끝).
        let dest = controller.tabs(inPane: pane)
            .filter { $0.id != tabId }
            .reduce(0) { $0 + (groupRank(content(for: $1.id)) <= rank ? 1 : 0) }
        _ = controller.reorderTab(tabId, toIndex: dest)
    }

    /// diff를 문서/diff 그룹 탭의 서브탭으로 연다.
    @discardableResult
    func openDiff(_ target: GitDiffTarget) -> TabID? {
        openInGroup(.diff(target))
    }

    /// 파일을 문서 그룹 탭의 서브탭으로 연다. 종류(md/코드)는 렌더에서 FileViewTarget.kind로 분기.
    @discardableResult
    func openFile(_ path: String) -> TabID? {
        openInGroup(.file(FileViewTarget(path: path)))
    }

    /// 그룹 탭 상태 접근 — BonsplitWorkspaceView가 .group 탭 렌더 시 사용.
    func group(for tabId: TabID) -> TabGroupState? { groups[tabId] }

    /// 서브탭 닫기 → 그룹이 비면 그룹 탭 자체를 닫는다.
    func closeGroupItem(_ tabId: TabID, itemId: String) {
        guard let state = groups[tabId] else { return }
        if state.remove(itemId) {
            _ = controller.closeTab(tabId) // didCloseTab에서 groups 정리
        }
    }

    // MARK: 2단 탭 — 문서/diff는 종류별 그룹 탭 하나에 서브탭으로 모은다
    //
    // 상단 탭바엔 종류별 그룹 탭([문서]/[변경])이 하나씩 서고, 그 아래에 서브탭(개별 파일/커밋)이
    // 뜬다. 같은 항목을 다시 열면 그 그룹을 선택하고 해당 서브탭으로 전환한다.

    @discardableResult
    private func openInGroup(_ item: GroupItemContent) -> TabID? {
        let kind = item.kind
        // 1) 이미 어느 그룹에 이 항목이 있으면 그 그룹 선택 + 서브탭 선택.
        if let (tabId, state) = groups.first(where: { $0.value.items.contains { $0.id == item.id } }) {
            state.selectedId = item.id
            controller.selectTab(tabId)
            return tabId
        }
        let pane = controller.focusedPaneId
        // 2) 포커스 패인에 같은 종류 그룹 탭이 있으면 거기에 서브탭 추가.
        if let pane, let tabId = groupTab(ofKind: kind, inPane: pane) {
            groups[tabId]?.add(item)
            controller.selectTab(tabId)
            return tabId
        }
        // 3) 새 그룹 탭 생성.
        guard let tabId = controller.createTab(title: kind.title, icon: kind.icon, inPane: pane) else { return nil }
        tabContent[tabId] = .group(kind)
        groups[tabId] = TabGroupState(first: item)
        regroup(tabId, inPane: pane)
        controller.selectTab(tabId)
        return tabId
    }

    /// 패인 안에서 주어진 종류의 그룹 탭을 찾는다(종류별 최대 1개).
    private func groupTab(ofKind kind: TabGroupKind, inPane pane: PaneID) -> TabID? {
        controller.tabs(inPane: pane).first { tab in
            if case .group(let k) = content(for: tab.id) { return k == kind }
            return false
        }?.id
    }

    /// 최초 표시 시: 저장된 트리가 있으면 복원, 없으면 초기 터미널 1개.
    func ensureInitialTerminal() {
        guard !initialized else { return }
        initialized = true
        // Bonsplit이 컨트롤러 생성 시 자동으로 넣는 "Welcome"/star 탭. muxa가 트리를 소유하므로
        // 저장 트리 복원(또는 새 터미널)으로 실제 탭을 만든 뒤 이 부트스트랩 탭을 닫는다.
        let bootstrapTabs = Set(controller.allTabIds)
        if let tree = restoreTree {
            restoreTree = nil
            restore(tree)
        } else {
            newTerminal()
        }
        // 실제(비-bootstrap) 탭을 먼저 선택한 뒤 welcome을 닫는다 — selected였던 welcome을 그냥 닫으면
        // 선택 탭이 사라져 빈 화면이 된다(터미널 안 뜸의 원인).
        let realTabs = controller.allTabIds.filter { !bootstrapTabs.contains($0) }
        if let first = realTabs.first {
            controller.selectTab(first)
            for id in bootstrapTabs { _ = controller.closeTab(id) }
        }
        // 복원/신규가 아무 탭도 못 만들었으면 bootstrap 탭을 터미널로 라벨링해 남긴다(빈 화면 방지).
        if controller.allTabIds.isEmpty {
            newTerminal()
        } else {
            for id in controller.allTabIds { controller.updateTab(id, title: "터미널", icon: "terminal") }
        }
        // 터미널 복원 후 문서/커밋 diff를 다시 연다(그룹 탭으로 재생성).
        let viewers = restoreViewers
        restoreViewers = []
        let firstTerminal = controller.allTabIds.first
        for v in viewers {
            if let f = v.file { _ = openFile(f) }
            else if let h = v.commit { _ = openDiff(.commit(hash: h, subject: v.commitSubject ?? h)) }
        }
        // 복원 직후엔 터미널을 앞에 둔다(뷰어가 선택된 채 뜨지 않게).
        if let firstTerminal { controller.selectTab(firstTerminal) }
    }

    /// 세션 저장용 — 열린 문서/커밋 diff 목록(순서 보존). 파일 diff는 제외.
    func savedViewers() -> [SavedViewer] {
        var out: [SavedViewer] = []
        for state in groups.values {
            for item in state.items {
                switch item {
                case .file(let t):
                    out.append(SavedViewer(file: t.path, commit: nil, commitSubject: nil))
                case .diff(let target):
                    if case .commit(let hash, let subject) = target {
                        out.append(SavedViewer(file: nil, commit: hash, commitSubject: subject))
                    }
                }
            }
        }
        return out
    }

    // MARK: 세션 레이아웃 저장 — 뷰어/diff 탭을 뺀 터미널 전용 스냅샷
    //
    // PTY는 복원 불가라 각 패인의 '터미널 탭 수'만 복원에 의미가 있고, 뷰어(md/코드)·diff는
    // 열려 있던 파일/커밋을 다시 띄우는 게 아니라 새 터미널로 되살아나면 오히려 잘못이다.
    // 저장 시 이들을 걸러 분할 구조 + 터미널만 남긴다.

    /// 세션 저장용 트리(터미널 탭만). AppState.save가 treeSnapshot 대신 이걸 쓴다.
    func layoutSnapshot() -> ExternalTreeNode {
        prune(controller.treeSnapshot())
    }

    private func prune(_ node: ExternalTreeNode) -> ExternalTreeNode {
        switch node {
        case .pane(let p):
            let terminalTabs = p.tabs.filter { tab in
                guard let uuid = UUID(uuidString: tab.id) else { return true }
                if case .terminal = content(for: TabID(uuid: uuid)) { return true }
                return false
            }
            // 터미널이 하나도 없으면 빈 패인이 되지 않게 1개는 남긴다(복원 시 새 터미널로 채워짐).
            let kept = terminalTabs.isEmpty ? Array(p.tabs.prefix(1)) : terminalTabs
            return .pane(ExternalPaneNode(id: p.id, frame: p.frame, tabs: kept, selectedTabId: p.selectedTabId))
        case .split(let s):
            return .split(ExternalSplitNode(id: s.id, orientation: s.orientation, dividerPosition: s.dividerPosition,
                                            first: prune(s.first), second: prune(s.second)))
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
