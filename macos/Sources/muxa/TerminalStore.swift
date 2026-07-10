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
    /// 탭/뷰어 구성이 바뀔 때 상위(AppState)에 알린다 — 즉시 세션 저장(⌘Q 없이도 복원되게).
    @ObservationIgnored var onStateChange: (() -> Void)?
    /// 초기 복원이 끝난 뒤에만 저장을 트리거한다(복원 중 중간 상태 저장 방지).
    @ObservationIgnored private var ready = false

    private func persist() { if ready { onStateChange?() } }

    var hasBadge: Bool { !badgedTabs.isEmpty }

    /// 이 스토어(프로젝트)의 시작 폴더 — diff/뷰어 탭이 참조한다.
    var workingDir: String? { cwd }

    /// 최초 표시 시 복원할 통합 레이아웃 스냅샷(없으면 초기 터미널 1개). ensureInitialTerminal에서 소비.
    @ObservationIgnored private var restoreSnap: PaneSnapshot?
    /// 복원 replay 중에는 delegate 부작용(자동 새 터미널 생성)을 막는다.
    @ObservationIgnored private var restoring = false
    /// ensureInitialTerminal 1회 보장 — Bonsplit이 초기 "Welcome" 탭을 넣어 allTabIds가 비지 않으므로 플래그로 판별.
    @ObservationIgnored private var initialized = false

    init(app: ghostty_app_t, cwd: String?, restoreSnap: PaneSnapshot? = nil) {
        self.app = app
        self.cwd = cwd
        self.restoreSnap = restoreSnap
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
        persist()
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
        persist()
        return id
    }

    // MARK: 탭 그룹핑 — 같은 종류끼리 묶기 (터미널 | 문서 | diff)
    //
    // 탭바에서 "문서는 문서끼리, diff는 diff끼리" 인접하도록 종류별 rank로 정렬 위치를 잡는다.
    // 복원 중엔 저장된 순서를 존중하므로 건너뛴다.

    /// 탭 종류 정렬 순위 — 터미널(0) < 문서(1) < HTML(2) < 코드(3) < 변경(4). 같은 순위는 생성 순서 유지.
    private func groupRank(_ content: TabContent) -> Int {
        switch content {
        case .terminal: return 0
        case .group(.documents): return 1
        case .group(.html): return 2
        case .group(.code): return 3
        case .group(.diffs): return 4
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

    /// diff를 변경 그룹 탭의 서브탭으로 연다.
    @discardableResult
    func openDiff(_ target: GitDiffTarget) -> TabID? {
        let id = openInGroup(.diff(target)); persist(); return id
    }

    /// 파일을 종류별(문서/HTML/코드) 그룹 탭의 서브탭으로 연다.
    @discardableResult
    func openFile(_ path: String) -> TabID? {
        let id = openInGroup(.file(FileViewTarget(path: path))); persist(); return id
    }

    /// 그룹 탭 상태 접근 — BonsplitWorkspaceView가 .group 탭 렌더 시 사용.
    func group(for tabId: TabID) -> TabGroupState? { groups[tabId] }

    /// 서브탭 닫기 → 그룹이 비면 그룹 탭 자체를 닫는다.
    func closeGroupItem(_ tabId: TabID, itemId: String) {
        guard let state = groups[tabId] else { return }
        if state.remove(itemId) {
            _ = controller.closeTab(tabId) // didCloseTab에서 groups 정리(+persist)
        } else {
            persist()
        }
    }

    // MARK: 2단 탭 — 문서/diff는 종류별 그룹 탭 하나에 서브탭으로 모은다
    //
    // 상단 탭바엔 종류별 그룹 탭([문서]/[변경])이 하나씩 서고, 그 아래에 서브탭(개별 파일/커밋)이
    // 뜬다. 같은 항목을 다시 열면 그 그룹을 선택하고 해당 서브탭으로 전환한다.

    @discardableResult
    private func openInGroup(_ item: GroupItemContent) -> TabID? {
        let kind = item.kind
        let pane = controller.focusedPaneId
        // dedup은 '포커스 패인' 기준 — 다른 패인에 같은 파일이 열려 있어도, 지금 활성 패인에 연다.
        // 1) 포커스 패인에 같은 종류 그룹 탭이 있으면 거기서 처리(add가 중복이면 선택만, 아니면 추가).
        if let pane, let tabId = groupTab(ofKind: kind, inPane: pane) {
            groups[tabId]?.add(item)
            controller.selectTab(tabId)
            return tabId
        }
        // 2) 없으면 포커스 패인에 새 그룹 탭 생성.
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

    /// 최초 표시 시: 저장된 스냅샷이 있으면 복원, 없으면 초기 터미널 1개.
    func ensureInitialTerminal() {
        guard !initialized else { return }
        initialized = true
        // Bonsplit이 컨트롤러 생성 시 자동으로 넣는 "Welcome"/star 탭. 실제 탭을 만든 뒤 이걸 닫는다.
        let bootstrap = Set(controller.allTabIds)
        if let snap = restoreSnap {
            restoreSnap = nil
            restoreLayout(snap)
        } else {
            _ = controller.createTab(title: "터미널", icon: "terminal", inPane: nil)
        }
        // 실제 탭이 생겼으면 부트스트랩 welcome을 닫는다(복원이 이미 선택을 잡았으므로 순서 안전).
        let real = controller.allTabIds.filter { !bootstrap.contains($0) }
        if !real.isEmpty {
            for id in bootstrap { _ = controller.closeTab(id) }
        }
        if controller.allTabIds.isEmpty {
            _ = controller.createTab(title: "터미널", icon: "terminal", inPane: nil)
        }
        ready = true // 이후 탭/뷰어 변경은 즉시 저장(⌘Q 없이도 복원되게)
    }

    // MARK: 세션 저장·복원 — 통합 스냅샷(트리 + 탭별 종류·payload). cmux 방식.
    //
    // PTY는 프로세스라 복원 불가 → 터미널은 워크스페이스 cwd에서 새 셸. 문서/커밋 diff는
    // 경로/해시로 재생성. 구조·순서·선택을 그대로 담아 단일 패스로 복원(선택 튐·빈 터미널 방지).

    /// 현재 레이아웃 → 저장 스냅샷. AppState.save가 사용.
    func snapshot() -> PaneSnapshot {
        convert(controller.treeSnapshot())
    }

    private func convert(_ node: ExternalTreeNode) -> PaneSnapshot {
        switch node {
        case .pane(let p):
            var tabs: [TabSnapshot] = []
            var selected = 0
            for (i, et) in p.tabs.enumerated() {
                guard let uuid = UUID(uuidString: et.id) else { continue }
                let tid = TabID(uuid: uuid)
                if et.id == p.selectedTabId { selected = tabs.count }
                switch content(for: tid) {
                case .terminal:
                    tabs.append(TabSnapshot(group: nil, items: [], selectedItem: 0))
                case .group(let kind):
                    let state = groups[tid]
                    let items = (state?.items ?? []).map(itemSnapshot)
                    let sel = state.flatMap { s in s.items.firstIndex { $0.id == s.selectedId } } ?? 0
                    if items.isEmpty { continue } // 빈 그룹은 저장하지 않음
                    tabs.append(TabSnapshot(group: kind.raw, items: items, selectedItem: sel))
                }
                _ = i
            }
            if tabs.isEmpty { tabs = [TabSnapshot(group: nil, items: [], selectedItem: 0)] } // 빈 패인 방지
            let focused = p.id == controller.focusedPaneId?.id.uuidString
            return .leaf(tabs: tabs, selected: min(selected, tabs.count - 1), focused: focused)
        case .split(let s):
            return .split(vertical: s.orientation == "vertical", divider: s.dividerPosition,
                          first: convert(s.first), second: convert(s.second))
        }
    }

    private func itemSnapshot(_ item: GroupItemContent) -> ItemSnapshot {
        switch item {
        case .file(let t): return ItemSnapshot(file: t.path, commit: nil, commitSubject: nil)
        case .diff(let target):
            if case .commit(let hash, let subject) = target {
                return ItemSnapshot(file: nil, commit: hash, commitSubject: subject)
            }
            return ItemSnapshot(file: nil, commit: nil, commitSubject: nil) // 파일 diff는 복원 대상 아님
        }
    }

    private func itemContent(_ s: ItemSnapshot) -> GroupItemContent? {
        if let f = s.file { return .file(FileViewTarget(path: f)) }
        if let h = s.commit { return .diff(.commit(hash: h, subject: s.commitSubject ?? h)) }
        return nil
    }

    /// 복원 중 만난 '활성 칸'과 그 칸의 선택 탭 — 재구성이 끝난 뒤 전역 포커스를 여기로 되돌린다.
    /// (realize가 리프마다 selectTab으로 포커스를 옮기므로, 마지막에 저장 시점의 활성 칸으로 복구해야 함.)
    @ObservationIgnored private var restoreFocus: (pane: PaneID, tab: TabID?)?

    /// 스냅샷을 현재 컨트롤러에 단일 패스로 재구성. 빈 패인 폴백은 ensureInitialTerminal이 담당.
    private func restoreLayout(_ snap: PaneSnapshot) {
        restoring = true
        restoreFocus = nil
        realize(snap, into: controller.allPaneIds.first)
        restoring = false
        // 활성 칸 복원 — 선택 탭이 있으면 selectTab(그 칸 포커스+탭 선택), 없으면 칸만 포커스.
        if let rf = restoreFocus {
            restoreFocus = nil
            if let tab = rf.tab { controller.selectTab(tab) } else { controller.focusPane(rf.pane) }
        }
    }

    /// 스냅샷 노드를 targetPane에 실현한다. leaf=탭들 생성+선택, split=쪼갠 뒤 양쪽 채움.
    private func realize(_ snap: PaneSnapshot, into pane: PaneID?) {
        guard let pane else { return }
        switch snap {
        case .leaf(let tabs, let selected, let focused):
            var created: [TabID] = []
            for t in tabs {
                if let raw = t.group, let kind = TabGroupKind(raw: raw) {
                    if let gid = realizeGroup(kind, items: t.items, selectedItem: t.selectedItem, inPane: pane) {
                        created.append(gid)
                    }
                } else if let tid = controller.createTab(title: "터미널", icon: "terminal", inPane: pane) {
                    created.append(tid)
                }
            }
            let selectedTab = selected < created.count ? created[selected] : nil
            if let selectedTab { controller.selectTab(selectedTab) }
            // 저장 시점의 활성 칸이면 재구성 후 전역 포커스를 여기로 되돌리게 기록해 둔다.
            if focused { restoreFocus = (pane, selectedTab) }
        case .split(let vertical, let divider, let first, let second):
            let orientation: SplitOrientation = vertical ? .vertical : .horizontal
            guard let newPane = controller.splitPane(pane, orientation: orientation, withTab: nil,
                                                     initialDividerPosition: CGFloat(divider)) else {
                realize(first, into: pane); realize(second, into: pane) // 분할 실패 → 평면화
                return
            }
            realize(first, into: pane)      // 기존 패인 = first
            realize(second, into: newPane)  // 새 패인 = second
        }
    }

    /// 그룹 탭 하나를 items로 재구성(첫 항목으로 생성 후 나머지 add). 선택 서브탭 복원.
    private func realizeGroup(_ kind: TabGroupKind, items: [ItemSnapshot], selectedItem: Int, inPane pane: PaneID) -> TabID? {
        var gid: TabID?
        for s in items {
            guard let content = itemContent(s) else { continue }
            if let id = gid {
                groups[id]?.add(content)
            } else if let id = controller.createTab(title: kind.title, icon: kind.icon, inPane: pane) {
                tabContent[id] = .group(kind)
                groups[id] = TabGroupState(first: content)
                gid = id
            }
        }
        if let id = gid, let state = groups[id], selectedItem < state.items.count {
            state.selectedId = state.items[selectedItem].id
        }
        return gid
    }
}
