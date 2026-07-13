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

    // 크롬 색(chromeColors)은 설정하지 않는다.
    //
    // `tabBarBackgroundHex`를 주면 활성 탭 대비는 조금 살지만, 분할 버튼 레인의 backdrop이
    // 그 색에서 파생돼 **불투명해진다**. 기본값은 반투명 크롬(.translucentChrome + masksTabContent)이라
    // 탭이 레인 아래로 흐릿하게 흘러가는데, 불투명해지면 탭이 레인 앞에서 뚝 잘린 것처럼 보인다.
    // 활성 탭 대비를 얻자고 탭바의 기본 동작을 깨는 건 남는 장사가 아니다 —
    // 탭 스타일을 정말 바꾸려면 Bonsplit을 포크해야 한다.

    @ObservationIgnored private let app: ghostty_app_t
    /// 새 셸의 기본 시작 폴더(= 프로젝트 경로, 없으면 워크스페이스 경로 상속).
    /// 워크스페이스 기본 경로가 바뀌면 AppState가 `updateCwd`로 갱신한다 — 이미 떠 있는 PTY는 못 옮기지만
    /// **앞으로 여는 터미널**은 새 폴더에서 시작해야 한다.
    @ObservationIgnored private var cwd: String?
    @ObservationIgnored private var terms: [TabID: TermView] = [:]
    /// 탭별로 새 셸을 띄울 작업 디렉터리 힌트. term(for:)가 TermView 생성 시 참조한다.
    /// 두 경로가 채운다 — 세션 복원(저장된 OSC 7 pwd)과 새 탭·분할(원본 칸의 현재 pwd 상속).
    /// TermView가 아직 안 만들어진 탭도 다음 저장 때 cwd를 잃지 않도록 convert의 폴백으로도 쓴다.
    @ObservationIgnored private var pendingCwd: [TabID: String] = [:]
    /// 이 워크스페이스에서 셸이 마지막으로 이동한 디렉터리(OSC 7). 원본 칸에 터미널이 없을 때(문서·diff 탭에
    /// 포커스가 있는 상태에서 분할 등) 새 셸의 시작 폴더 폴백으로 쓴다.
    @ObservationIgnored private var lastPwd: String?
    /// 복원된 탭의 스크롤백 파일 경로 힌트 — term(for:)가 새 셸에 env로 주입한다(④). pendingCwd와 같은 수명.
    @ObservationIgnored private var restoredScrollbackFile: [TabID: String] = [:]
    /// 탭별 에이전트 재개 바인딩(훅이 넘긴 재개 명령). 훅 알림으로 등록되고 스냅샷에 실려 복원된다.
    /// 값 자체는 관측 대상이 아니라 뷰는 아래 resumeTabs로 표시 여부만 반응한다.
    @ObservationIgnored private var resumeBindings: [TabID: ResumeBinding] = [:]
    /// 재개 바인딩이 살아 있는 탭들 — 재개 배너(ResumeOverlay)가 관측해 표시/소비를 반응한다.
    /// resumeBindings와 항상 동기(등록 시 insert, 소비·탭닫힘 시 remove) — 뷰가 값 대신 이 집합만 본다.
    private(set) var resumeTabs: Set<TabID> = []
    /// 복원된 세션 재개의 승인 게이트(off/manual/auto). 기본 manual — 임의 셸 명령 자동 실행을 막는다(신뢰 경계).
    /// 설정 라이브 리로드로 갱신될 수 있어 var — AppState가 `updateAgentResumeMode`로 전파한다. (D2)
    @ObservationIgnored private(set) var agentResumeMode: AgentResumeMode
    /// 직전 실행이 더티(비정상) 종료였는지 — AppState가 시작 시 판정해 넘긴다(세션 상수라 관측 대상 아님).
    /// 재개 전략(ResumeStrategy)에만 쓴다: manual일 때 배너를 "비정상 종료 후 복원됨"으로 강조한다.
    @ObservationIgnored private let sessionWasDirty: Bool
    /// 터미널이 아닌 탭의 종류(그룹). 없으면 .terminal.
    @ObservationIgnored private var tabContent: [TabID: TabContent] = [:]
    /// 그룹 탭(TabID) → 서브탭 상태(문서·diff 묶음). TabGroupView가 관측한다.
    @ObservationIgnored private var groups: [TabID: TabGroupState] = [:]

    /// 탭별 현재 셸 작업 디렉터리(OSC 7) — 상태바가 활성 칸의 pwd를 보여준다.
    /// TermView는 NSView라 SwiftUI가 관측하지 못해, onPwd 콜백으로 여기 미러링한다(관측 대상).
    private(set) var pwds: [TabID: String] = [:]

    /// 백그라운드 활동(●)으로 배지가 붙은 탭들(A). 프로젝트 배지가 이걸 파생·관측한다.
    var badgedTabs: Set<TabID> = []
    /// 마지막으로 뷰어 탭으로 연 파일 경로 — 익스플로러가 관측해 그 노드로 reveal(펼침+선택+스크롤).
    var lastOpenedFilePath: String?
    /// reveal 트리거 시퀀스 — 같은 파일을 다시 열어도 재-reveal 되도록 매 openFile마다 증가.
    var revealSeq = 0
    /// 지금 활동 테두리가 깜빡이는 칸들 — 그 칸의 선택 탭 TabID 기준. BonsplitWorkspaceView가 관측해 overlay를 그린다.
    /// 보이는 칸에서 활동(완료·벨·알림)이 나면 잠깐 켰다 페이드로 끈다. 배지(안 보이는 탭)와 상호배타적 신호.
    private(set) var flashingTabs: Set<TabID> = []
    /// 탭별 추정 에이전트 활동 상태(작업중/대기/완료/idle) — BonsplitWorkspaceView가 관측해 상시 상태 테두리를 그린다.
    /// idle은 담지 않는다(없음=idle) — 상태가 바뀔 때만 immutable 교체해 SwiftUI 갱신을 최소화한다.
    private(set) var agentActivity: [TabID: AgentActivity] = [:]
    /// 배지가 하나라도 생기면 상위(AppState)에 알린다 — 프로젝트 탭 ● 표시용.
    @ObservationIgnored var onProjectActivity: (() -> Void)?
    /// 데스크톱 알림을 띄워야 할 때 상위(AppState)에 위임한다 — 라우팅 컨텍스트(프로젝트·워크스페이스)는
    /// 스토어가 모르므로 AppState가 붙인다. 이 스토어는 tabId·제목·본문만 넘긴다.
    @ObservationIgnored var onNotify: ((TabID, String, String) -> Void)?
    /// 배지가 붙는(=안 보이는 탭에 주의가 쌓이는) 순간 상위(AppState)에 알린다 — 알림 인박스 이력용.
    /// 라우팅 컨텍스트는 AppState가 붙이므로 tabId·종류·제목만 넘긴다.
    @ObservationIgnored var onAttention: ((TabID, AttentionKind, String) -> Void)?
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
    /// 관측 대상(뷰가 showEmptyState에서 읽음) — 초기화 전엔 빈 상태 뷰를 띄우지 않게 게이트한다.
    private(set) var initialized = false
    /// 이 스토어에 살아있는 탭이 하나라도 있는지(관측 대상). controller.allTabIds는 관측 불가라
    /// 탭 생성·닫기 경계에서 syncHasTabs로 동기화한다 — 뷰가 빈 상태 분기에 쓴다.
    private(set) var hasTabs = false

    /// 메인 영역에 빈 상태 뷰("터미널 없음")를 띄울지 — 초기화가 끝났는데 살아있는 탭이 하나도 없을 때만.
    /// 초기화 전(ensureInitialTerminal 이전)엔 곧 초기 터미널이 생기므로 빈 상태를 띄우지 않는다(깜빡임 방지).
    var showEmptyState: Bool { initialized && !hasTabs }

    /// 관측 가능한 hasTabs를 컨트롤러 실제 상태로 맞춘다 — 탭 수가 0↔양수로 바뀌는 경계에서 호출한다.
    private func syncHasTabs() {
        let next = !controller.allTabIds.isEmpty
        if hasTabs != next { hasTabs = next }
    }

    init(app: ghostty_app_t, cwd: String?, restoreSnap: PaneSnapshot? = nil,
         commandFinishedThresholdNs: UInt64 = 8_000_000_000,
         agentResumeMode: AgentResumeMode = .manual,
         sessionWasDirty: Bool = false) {
        self.app = app
        self.cwd = cwd
        self.restoreSnap = restoreSnap
        self.commandFinishedThresholdNs = commandFinishedThresholdNs
        self.agentResumeMode = agentResumeMode
        self.sessionWasDirty = sessionWasDirty
        // keepAllAlive — 탭 전환 시 뷰(WKWebView 뷰어·터미널)를 파괴/재생성하지 않고 유지한다.
        // 기본 .recreateOnSwitch는 전환마다 뷰어를 재로드(굼뜸·상태 손실)해서 부적합.
        var config = BonsplitConfiguration(contentViewLifecycle: .keepAllAlive)
        // 탭바 내장 액션 버튼: [새 터미널(+), 우측 분할, 하단 분할]. 브라우저는 muxa에 없어 제외.
        // .newTerminal → requestNewTab(kind:"terminal") → didRequestNewTab 델리게이트 → newTerminal().
        config.appearance.splitButtons = [.newTerminal, .splitRight, .splitDown]
        // 칸 탭바를 도구 패널(탐색기·git) 헤더와 같은 높이로 — 두 줄이 한 선에 이어져 보이게.
        config.appearance.tabBarHeight = RowHeight.header
        // 탭 폭 모드는 기본(.fixed)을 유지한다.
        // .fill로 바꾸면 탭이 "분할 버튼 레인을 뺀 폭"에 맞춰져, 탭 스크롤이 레인 앞에서 끊긴다
        // (원래는 탭이 레인 아래로 흘러가며 페이드된다 — 그 동작이 옳다).
        self.controller = BonsplitController(configuration: config)
        super.init()
        controller.delegate = self

        // 파일 드롭은 **반드시 Bonsplit을 통해** 받는다. Bonsplit이 패인마다 `.onDrop(of: [.tabTransfer, .fileURL])`을
        // 깔아두므로(PaneContainerView), 파일 드래그의 목적지는 그 중첩 호스팅 뷰가 된다. 핸들러를 안 걸면
        // Bonsplit이 드롭을 거부하고, AppKit은 거부된 목적지에서 조상 뷰로 폴백하지 않아 드롭이 통째로 죽는다.
        controller.onFileDrop = { [weak self] urls, paneId in
            self?.insertDroppedPaths(urls.map(\.path), inPane: paneId) ?? false
        }
    }

    /// 드롭된 경로를 그 칸의 터미널 프롬프트에 셸-이스케이프해 삽입한다 — claude code는 삽입된 이미지 경로를
    /// 인식해 첨부한다. 실행(Enter)은 사용자 몫이라 개행 없이 넣기만 한다. 터미널이 아닌 탭(diff 뷰어 등)은 사양한다.
    private func insertDroppedPaths(_ paths: [String], inPane paneId: PaneID) -> Bool {
        guard !paths.isEmpty,
              let tab = controller.selectedTab(inPane: paneId),
              case .terminal = content(for: tab.id) else { return false }
        controller.focusPane(paneId)
        term(for: tab.id).sendText(TerminalDrop.insertionText(for: paths))
        return true
    }

    deinit {
        idleTimer?.invalidate() // idle 추정 타이머가 런루프에 남지 않게 정리(작업 중 스토어가 해제되는 드문 경우).
    }

    /// 완료 배지 임계(ns)를 갱신한다 — 설정 라이브 리로드 시 AppState가 이미 실행 중인 스토어에도 전파한다.
    /// 다음 명령 완료 판정부터 새 값이 적용된다(진행 중 판정은 그대로).
    /// 기본 시작 폴더를 바꾼다(워크스페이스 기본 경로 변경). 살아 있는 터미널은 그대로 두고
    /// 앞으로 여는 탭·분할부터 새 폴더에서 시작한다 — 프로세스의 cwd는 밖에서 바꿀 수 없다.
    func updateCwd(_ path: String?) {
        cwd = path
    }

    func updateCommandFinishedThreshold(_ ns: UInt64) {
        commandFinishedThresholdNs = ns
    }

    /// 재개 승인 게이트 모드를 갱신한다 — 설정 라이브 리로드 시 AppState가 실행 중 스토어에도 전파한다. (D2)
    /// 이미 뜬 재개 배너의 다음 판정부터 새 값이 적용된다.
    func updateAgentResumeMode(_ mode: AgentResumeMode) {
        agentResumeMode = mode
    }

    // MARK: BonsplitDelegate — 분할·새탭·닫기에 터미널 생명주기를 잇는다

    /// 분할 즉시 새 패인에 터미널을 만든다 — 빈 패인을 거치지 않는다(muxa 원래 동작).
    /// 새 셸은 분할 원본 칸의 현재 작업 디렉터리를 이어받는다.
    /// 복원 중엔 replay가 탭을 직접 채우므로 자동 생성을 건너뛴다.
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        if restoring { return }
        newTerminal(inPane: newPane, inheritingFrom: originalPane)
    }

    /// 탭바 `+` 버튼 → 새 터미널.
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
        newTerminal(inPane: pane)
    }

    /// 탭이 닫히면 그 터미널(PTY·서피스)·뷰어 상태를 해제한다.
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {
        terms[tabId] = nil // TermView deinit이 서피스 free
        pendingCwd[tabId] = nil // 시작 cwd 힌트 해제
        restoredScrollbackFile[tabId] = nil // 스크롤백 파일 힌트 해제
        ScrollbackStore.delete(for: tabId) // 이 탭의 스크롤백 파일 정리(누수 방지)
        resumeBindings[tabId] = nil // 에이전트 재개 바인딩 해제
        resumeTabs.remove(tabId) // 재개 배너 표시 상태도 해제
        tabContent[tabId] = nil
        groups[tabId] = nil // 그룹 탭이면 서브탭 상태도 해제
        badgedTabs.remove(tabId)
        flashingTabs.remove(tabId) // 활동 테두리 상태 해제
        flashSeq[tabId] = nil
        clearAgentActivity(tabId) // 에이전트 추정 상태·추정기 해제(+ idle 타이머 재동기화)
        lastBellAt[tabId] = nil // 벨 디바운스 상태 해제
        resetCoalescers(for: tabId) // 배지·알림 병합 이력 해제(맵 누수 방지)
        manualTitles[tabId] = nil // 수동 지정 제목 해제
        engineTitles[tabId] = nil // 엔진 제목 캐시 해제
        syncHasTabs() // 마지막 탭이 닫히면 빈 상태 뷰로 전환(관측 갱신)
        persist()
    }

    /// 탭바(Bonsplit) 컨텍스트 메뉴 액션. Bonsplit이 자체 NSMenu로 띄우고 선택 결과만 여기로 넘긴다
    /// (메뉴를 커스텀 뷰로 갈아끼울 확장점이 라이브러리에 없어 이 메뉴만 시스템 스타일이다).
    /// 처리하지 않는 액션(브라우저·SSH·fork 등 muxa에 없는 기능)은 메뉴에도 뜨지 않는다.
    func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Tab, inPane pane: PaneID) {
        switch action {
        case .rename: promptRenameTab(tab.id)
        case .clearName: clearTabName(tab.id)
        case .closeOthers: closeTabs(inPane: pane) { $0.id != tab.id }
        case .closeToLeft: closeTabs(inPane: pane, side: .left, of: tab.id)
        case .closeToRight: closeTabs(inPane: pane, side: .right, of: tab.id)
        case .newTerminalToRight: newTerminal(inPane: pane)
        case .copyIdentifiers: copyTabId(tab.id)
        default: break
        }
    }

    private enum TabSide { case left, right }

    /// 기준 탭의 한쪽에 있는 탭을 모두 닫는다(탭바 메뉴의 "왼쪽/오른쪽 탭 닫기").
    private func closeTabs(inPane pane: PaneID, side: TabSide, of tabId: TabID) {
        let tabs = controller.tabs(inPane: pane)
        guard let pivot = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let range = side == .left ? tabs[..<pivot] : tabs[(pivot + 1)...]
        let doomed = Set(range.map(\.id))
        closeTabs(inPane: pane) { doomed.contains($0.id) }
    }

    /// 조건에 맞는 탭을 닫는다. 닫는 도중 목록이 바뀌므로 대상 id를 먼저 확정한 뒤 지운다.
    private func closeTabs(inPane pane: PaneID, where predicate: (Tab) -> Bool) {
        for id in controller.tabs(inPane: pane).filter(predicate).map(\.id) {
            _ = controller.closeTab(id, inPane: pane)
        }
    }

    /// 탭 id를 클립보드로 — muxa notify 등 훅에서 이 칸을 지목할 때 쓴다(MUXA_TAB_ID와 같은 값).
    private func copyTabId(_ tabId: TabID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tabId.uuid.uuidString, forType: .string)
    }

    // MARK: 탭 명명 — 자동(SET_TITLE) + 수동 rename
    //
    // 엔진(셸 OSC 0/2)이 보낸 제목으로 탭 이름을 자동 갱신하되, 사용자가 수동 지정한 탭은 덮지 않는다.
    // manualTitles가 플래그 겸 값이고, engineTitles는 수동 해제 시 되돌릴 최신 자동 제목을 캐시한다.

    /// 새 터미널·복원 시 탭의 기본 이름.
    static let defaultTerminalTitle = "터미널"

    /// 사용자가 수동 지정한 탭 제목(tabId→제목). 존재하면 엔진 제목이 덮지 않는다.
    @ObservationIgnored private var manualTitles: [TabID: String] = [:]
    /// 엔진이 마지막으로 보낸 제목 — 수동 제목 해제 시 이 값으로 되돌린다.
    @ObservationIgnored private var engineTitles: [TabID: String] = [:]

    /// 엔진(SET_TITLE)이 보낸 제목을 탭에 반영한다 — 터미널 탭만, 수동 지정 탭은 건드리지 않는다.
    private func applyEngineTitle(_ raw: String, for tabId: TabID) {
        guard case .terminal = content(for: tabId) else { return } // 그룹 탭은 종류 제목 유지
        // 셸 기본 제목("user@host:~/path")은 탭 폭에 안 들어가 잘린다 — 마지막 폴더 이름만 남긴다.
        let title = TabTitle.shorten(raw)
        guard !title.isEmpty else { return }
        engineTitles[tabId] = title
        guard manualTitles[tabId] == nil else { return } // 수동 지정 우선
        controller.updateTab(tabId, title: title)
    }

    /// 사용자가 탭 이름을 수동 지정한다 — 이후 엔진 제목은 무시된다.
    func renameTab(_ tabId: TabID, to raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        manualTitles[tabId] = title
        controller.updateTab(tabId, title: title, hasCustomTitle: true)
        persist()
    }

    /// 수동 제목을 해제하고 자동 명명으로 되돌린다(최신 엔진 제목 없으면 기본값).
    func clearTabName(_ tabId: TabID) {
        guard manualTitles[tabId] != nil else { return }
        manualTitles[tabId] = nil
        let fallback = engineTitles[tabId] ?? Self.defaultTerminalTitle
        controller.updateTab(tabId, title: fallback, hasCustomTitle: false)
        persist()
    }

    /// 탭 이름 변경 입력 시트(NSAlert + 텍스트 필드). 확정하면 renameTab.
    /// 탭바 메뉴(Bonsplit)와 칸 우클릭 메뉴(TerminalPaneMenu)가 함께 쓴다.
    func promptRenameTab(_ tabId: TabID) {
        let alert = NSAlert()
        alert.messageText = "탭 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = tabTitle(tabId)
        field.placeholderString = Self.defaultTerminalTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            renameTab(tabId, to: field.stringValue)
        }
    }

    /// 현재 포커스된 패인의 터미널(단축키 대상 — ⌘F 등). diff 등 비-터미널 탭이면 nil.
    var focusedTerm: TermView? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane),
              case .terminal = content(for: tab.id) else { return nil }
        return term(for: tab.id)
    }

    /// 칸→탭 순서로 만나는 첫 터미널(포커스가 diff 등 비-터미널일 때의 폴백). 없으면 nil.
    private var firstTerminal: TermView? {
        for paneId in controller.allPaneIds {
            for tab in controller.tabs(inPane: paneId) where terms[tab.id] != nil {
                if case .terminal = content(for: tab.id) { return term(for: tab.id) }
            }
        }
        return nil
    }

    /// 외부 텍스트(리뷰 코멘트 등)를 에이전트 터미널에 붙여 다음 턴 지시로 되먹인다. 포커스가 diff면 첫 터미널로.
    /// 실행(Enter)은 커밋하지 않고 붙여넣기만 한다 — 사용자가 내용을 확인하고 직접 제출하게 둔다(신뢰 경계).
    /// 보낼 터미널이 없으면 false.
    @discardableResult
    func injectToTerminal(_ text: String) -> Bool {
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text // 끝 개행 = Enter 오해 방지
        guard let term = focusedTerm ?? firstTerminal, !body.isEmpty else { return false }
        term.sendText(body)
        return true
    }

    /// 탭의 내용 종류(터미널이거나 diff 등 뷰어).
    func content(for tabId: TabID) -> TabContent {
        tabContent[tabId] ?? .terminal
    }

    /// tabId에 대응하는 터미널 뷰(없으면 생성). 패인 내용 렌더에서 호출한다.
    func term(for tabId: TabID) -> TermView {
        if let t = terms[tabId] { return t }
        // tabId·소켓 경로를 셸 env로 주입(훅 알림용) — TermView.init에서 서피스 생성 전에 심는다.
        // 복원·상속 힌트가 있으면 그 디렉터리에서, 없으면 워크스페이스 기본 cwd에서 새 셸.
        let t = TermView(app: app, cwd: pendingCwd[tabId] ?? cwd, tabId: tabId, sockPath: NotifyServer.socketPath,
                         restoreScrollbackFile: restoredScrollbackFile[tabId])
        // 콜백은 action_cb(메인 async)·becomeFirstResponder(메인)에서만 불린다 → assumeIsolated 안전.
        t.onSignal = { [weak self] signal in MainActor.assumeIsolated { self?.handleSignal(signal, from: tabId) } }
        t.onClearBadge = { [weak self] tid in MainActor.assumeIsolated { self?.clearTabBadge(tid) } }
        // 셸 종료 → 이 탭만 닫는다(앱 종료 아님). closeTab→didCloseTab→terms[tid]=nil→TermView deinit이
        // 서피스를 free한다. close_surface_cb는 요청일 뿐 libghostty가 직접 free하지 않아 이중 free 아님.
        t.onRequestClose = { [weak self] tid in
            MainActor.assumeIsolated { _ = self?.controller.closeTab(tid) }
        }
        t.onTitle = { [weak self] title in
            MainActor.assumeIsolated { self?.applyEngineTitle(title, for: tabId) }
        }
        t.onPwd = { [weak self] pwd in
            MainActor.assumeIsolated {
                self?.lastPwd = pwd
                self?.pwds[tabId] = pwd
            }
        }
        terms[tabId] = t
        return t
    }

    /// 백그라운드 활동으로 이 탭에 배지(●)를 켠다 — 탭 점(Bonsplit isDirty) + 프로젝트 알림 + 인박스 이력.
    /// 같은 (tabId,kind)가 cooldown 안에 다시 오면 병합해 억제한다 — 배지는 이미 켜져 있어 시각 손실 없이
    /// 인박스·프로젝트 알림 폭주만 접는다. 주의가 해소(clearTabBadge)되면 병합기가 리셋돼 다음 신호는 통과.
    private func markBadge(_ tabId: TabID, kind: AttentionKind, title: String) {
        let (admit, next) = badgeCoalescer.admitting(BadgeKey(tabId: tabId, kind: kind),
                                                     now: ProcessInfo.processInfo.systemUptime)
        badgeCoalescer = next
        guard admit else { return }
        badgedTabs.insert(tabId)
        controller.updateTab(tabId, isDirty: true)
        onProjectActivity?()
        onAttention?(tabId, kind, title)
    }

    /// 인박스 이력에 쓸 탭 제목 — 수동 지정 > 엔진 제목 > 기본값.
    private func tabTitle(_ tabId: TabID) -> String {
        manualTitles[tabId] ?? engineTitles[tabId] ?? Self.defaultTerminalTitle
    }

    /// 훅(NotifyServer)에서 온 결정론적 알림을 이 스토어가 소유한 탭으로 라우팅한다. 소유하면 true.
    /// 셸이 도는 탭은 반드시 TermView(=terms)가 생성돼 있으므로 terms 유무로 소유를 판정한다.
    /// waiting/done은 순수 배달 게이트(NotificationGate)가 카테고리·가시성으로 배달을 가르고,
    /// working(작업 재개)은 주의 해소로 보고 배지를 끈다. resume이 실려 오면 재개 바인딩을 등록한다
    /// (state 없이 바인딩만 오는 메시지도 있어 state는 옵셔널 — 없으면 상태 신호 없이 바인딩만 등록).
    @discardableResult
    func deliverNotify(tabId: TabID, state: NotifyState?, title: String, body: String,
                       category: NotifyCategory? = nil, resume: ResumeBinding? = nil) -> Bool {
        guard terms[tabId] != nil else { return false }
        if let resume { setResumeBinding(resume, for: tabId) }
        if let state {
            // 명시 신호는 상태 추정의 ground truth — 배지 경로와 별개로 추정기에 항상 고정 반영한다(DESIGN 4.5).
            applyAgentSignal(.explicit(state), to: tabId)
            switch state {
            case .waiting, .done:
                // category 미지정이면 state에서 파생(하위호환) — 게이트가 배달 방식을 결정한다.
                fireNotification(tabId, title: title, body: body,
                                 category: category ?? state.defaultCategory, kind: .notify)
            case .working:
                clearTabBadge(tabId)
            }
        }
        return true
    }

    /// 바인딩을 맵 + 관측 집합에 함께 넣는다(항상 동기). 훅 등록·복원 realize가 공유하는 단일 경로.
    private func registerResumeBinding(_ binding: ResumeBinding, for tabId: TabID) {
        resumeBindings[tabId] = binding
        resumeTabs.insert(tabId)
    }

    /// 탭의 에이전트 재개 바인딩을 등록한다(훅 알림 경로). 즉시 저장을 트리거해 영속에 반영한다.
    func setResumeBinding(_ binding: ResumeBinding, for tabId: TabID) {
        registerResumeBinding(binding, for: tabId)
        persist()
    }

    /// 탭의 에이전트 재개 바인딩(없으면 nil). 재개 배너가 라벨·명령 미리보기를 읽는 접근자.
    func resumeBinding(for tabId: TabID) -> ResumeBinding? {
        resumeBindings[tabId]
    }

    /// 이 탭의 재개 전략 — 배너(ResumeOverlay)가 이 값 하나로 표시·자동 실행·강조 라벨을 정한다.
    ///
    /// 신뢰(trusted) 바인딩(muxa 자가구성 `claude --resume`)은 승인 게이트를 건너뛰고 항상 자동 실행한다(제로설정).
    /// 명령이 검증된 고정 꼴이라 안전하기 때문. 단 `off`는 사용자의 명시적 전면 비활성이라 존중한다.
    /// 훅이 넘긴 임의 명령(trusted=false)은 기존대로 모드+더티 순수 판정(ResumeStrategy.decide)을 따른다(D2 경계).
    func resumeStrategy(for tabId: TabID) -> ResumeStrategy {
        if resumeBindings[tabId]?.trusted == true {
            return agentResumeMode == .off ? .none : .auto
        }
        return ResumeStrategy.decide(mode: agentResumeMode, wasDirty: sessionWasDirty)
    }

    /// 재개 바인딩을 소비(제거)한다 — 한 번 재개하면 중복 실행·배너 잔존을 막고, 소비를 영속에 반영해
    /// (스냅샷에서도 빠지므로) 재시작 후 이미 재개한 세션을 또 띄우지 않는다. (D2)
    func consumeResumeBinding(for tabId: TabID) {
        guard resumeBindings[tabId] != nil else { return }
        resumeBindings[tabId] = nil
        resumeTabs.remove(tabId)
        persist()
    }

    /// 복원된 에이전트 세션을 재개한다 — 재개 명령을 셸에 입력·실행하고 바인딩을 소비한다.
    ///
    /// 신뢰 경계(D2): command는 훅이 넘긴 임의 셸 명령이다. 승인 게이트(agent_resume)가 off면 실행하지 않고,
    /// manual은 사용자가 배너 버튼으로, auto는 복원 후 자동으로 여기를 호출한다. 어느 경로든 실행은 이 한 곳뿐이고,
    /// 소비가 뒤따라 중복 실행을 막는다(auto의 지연 재호출·onAppear 재발화도 바인딩이 없으면 무동작).
    func executeResume(for tabId: TabID) {
        guard agentResumeMode != .off,
              let binding = resumeBindings[tabId],
              let term = terms[tabId] else { return }
        term.sendText(binding.command + "\n") // 명령 + 실행(Return). sendText가 개행을 Enter로 커밋한다.
        consumeResumeBinding(for: tabId)
    }

    /// 알림/배지 클릭으로 이 탭을 앞으로 가져온다 — 그 칸을 선택·포커스하고 배지를 끈다.
    /// 소유(terms/groups에 존재)하지 않으면 무동작.
    func revealTab(_ tabId: TabID) {
        guard terms[tabId] != nil || groups[tabId] != nil else { return }
        controller.selectTab(tabId)
        clearTabBadge(tabId)
    }

    /// 빠른 전환기(⌘K): 이 스토어의 모든 탭(터미널·그룹)과 그룹 서브탭을 가벼운 값으로 열거한다.
    /// 배지 여부를 함께 실어 "대기 우선" 정렬을 상위(AppState)가 판단하게 한다. 순회 순서는
    /// 칸(pane)→탭 순이라 계층(칸›탭›서브탭)이 자연스럽게 나온다.
    func quickSwitchTabs() -> [QuickTab] {
        var result: [QuickTab] = []
        for paneId in controller.allPaneIds {
            for tab in controller.tabs(inPane: paneId) {
                var subs: [QuickSubTab] = []
                if case .group = content(for: tab.id), let g = groups[tab.id] {
                    subs = g.items.map { QuickSubTab(id: $0.id, title: $0.title, icon: $0.icon) }
                }
                result.append(QuickTab(tabId: tab.id, title: tab.title, icon: tab.icon,
                                       badged: badgedTabs.contains(tab.id), subItems: subs))
            }
        }
        return result
    }

    /// 빠른 전환기: 그룹 탭 안의 특정 서브탭을 선택한다(탭 선택·포커스는 revealTab이 이미 처리).
    /// 그룹 탭이 아니거나 항목이 없으면 무동작.
    func selectGroupItem(_ tabId: TabID, itemId: String) {
        groups[tabId]?.selectedId = itemId
    }

    /// 사용자가 탭을 보면 배지를 끈다. 상시 상태 테두리(waiting/done)도 함께 해제한다("봤음").
    /// 주의가 해소됐으니 이 탭의 병합 이력도 리셋한다 — 다음 신호는 cooldown에 걸리지 않고 곧장 통과.
    func clearTabBadge(_ tabId: TabID) {
        acknowledgeAgent(tabId)
        resetCoalescers(for: tabId)
        guard badgedTabs.contains(tabId) else { return }
        badgedTabs.remove(tabId)
        controller.updateTab(tabId, isDirty: false)
    }

    /// 한 탭의 배지·알림 병합 이력을 지운다(주의 해소·탭 종료 시) — 맵 무한 성장 방지 + 오억제 방지.
    private func resetCoalescers(for tabId: TabID) {
        badgeCoalescer = badgeCoalescer.resetting { $0.tabId == tabId }
        notifyCoalescer = notifyCoalescer.resetting { $0 == tabId }
    }

    /// 사용자가 탭을 봤다 — waiting/done 상시 테두리를 지운다(추정기를 idle로 리셋해 고정도 푼다).
    /// 에이전트가 실제로 아직 작업 중이면 다음 출력 heartbeat가 곧 working으로 되세운다(working은 테두리 없음).
    private func acknowledgeAgent(_ tabId: TabID) {
        guard let est = estimators[tabId], est.state == .waiting || est.state == .done else { return }
        estimators[tabId] = AgentActivityEstimator(idleThreshold: est.idleThreshold)
        if agentActivity[tabId] != nil {
            var map = agentActivity
            map[tabId] = nil
            agentActivity = map
        }
        syncIdleTimer()
    }

    // MARK: 백그라운드 주의 신호 — 오탐 억제 후 배지/알림 (알림 신뢰도)
    //
    // TermView는 신호 종류만 넘기고, 여기서 "보이나?"·"울릴 가치가 있나?"를 판정한다.
    // 3~4분할 동시 감시에서 비포커스여도 화면에 보이는 칸(그 칸의 선택 탭)은 배지를 억제한다.

    /// 정상 종료(코드 0/미보고)면서 이 시간(ns)보다 짧게 끝난 명령은 배지를 억제한다.
    /// 짧은 `ls`·`cd` 완료로 배지가 쌓이는 오탐 방지. 기본 8초 — muxa 설정
    /// `command_finished_threshold_sec`로 덮인다(AppState가 init에 주입). (DESIGN 4.6)
    /// 설정 라이브 리로드로 갱신될 수 있어 var — AppState가 `updateCommandFinishedThreshold`로 전파한다.
    @ObservationIgnored private var commandFinishedThresholdNs: UInt64
    /// 마지막 벨로부터 이 시간(초) 안쪽 벨은 무시 — 벨 연타 오탐 억제.
    private static let bellDebounce: TimeInterval = 1.0

    /// 탭별 마지막 벨 시각(systemUptime, 단조 증가) — 디바운스용.
    @ObservationIgnored private var lastBellAt: [TabID: TimeInterval] = [:]

    // MARK: 알림 dedup/coalescing — 같은 탭 연속 신호 병합 (cmux 대조)
    //
    // auto-approve로 도구를 연타하면 같은 탭 배지·시스템 알림이 폭주한다. cooldown 안의 반복만 접고
    // 진짜 새 신호(다른 (tab,kind)·cooldown 밖)는 통과시킨다. 판정은 순수 SignalCoalescer가, 상태 소유는 store.

    /// 배지 병합 키 — 같은 탭·같은 종류의 연속 배지만 접는다(다른 종류는 별개 주의라 통과).
    private struct BadgeKey: Hashable {
        let tabId: TabID
        let kind: AttentionKind
    }
    /// 같은 (tabId,kind) 배지가 이 시간(초) 안에 다시 오면 병합(억제) — 인박스·프로젝트 알림 폭주 방지.
    private static let badgeCoalesceCooldown: TimeInterval = 2.0
    /// 같은 탭 시스템 알림이 이 시간(초) 안에 다시 오면 병합(억제) — 가장 시끄러운 채널이라 더 길게.
    private static let notifyCoalesceCooldown: TimeInterval = 3.0
    /// 배지 병합기(순수 값) — markBadge의 단일 choke point에서 태운다.
    @ObservationIgnored private var badgeCoalescer = SignalCoalescer<BadgeKey>(cooldown: TerminalStore.badgeCoalesceCooldown)
    /// 시스템 알림 병합기(순수 값, 탭 단위) — fireNotification의 systemNotification 채널에서만 태운다.
    @ObservationIgnored private var notifyCoalescer = SignalCoalescer<TabID>(cooldown: TerminalStore.notifyCoalesceCooldown)

    /// 활동 테두리 유지 시간(ns) — 짧은 플래시로 충분(상시 테두리는 focus와 혼동). 1.2초.
    private static let flashDurationNs: UInt64 = 1_200_000_000
    /// 재-트리거 시 이전 해제 타이머를 무효화하려는 탭별 세대값 — 연속 활동이면 페이드가 리셋된다.
    @ObservationIgnored private var flashSeq: [TabID: Int] = [:]

    // MARK: 에이전트 상태 추정 (DESIGN 4.5) — 순수 추정기 + 신호 배선
    //
    // 탭별 AgentActivityEstimator(순수 값)에 신호(heartbeat·완료·명시 notify·tick)를 넣어 상태를 굴린다.
    // 명시 신호(muxa notify)가 ground truth로 우선하고, 없으면 출력 idle 타이머로 추정한다(보수적).

    /// 탭별 추정기(순수 값). agentActivity(관측 대상)는 여기서 파생한다.
    @ObservationIgnored private var estimators: [TabID: AgentActivityEstimator] = [:]
    /// working 추정 중인 탭이 있을 때만 도는 idle 점검 타이머 — 없으면 CPU를 쓰지 않게 껐다 켠다.
    @ObservationIgnored private var idleTimer: Timer?
    /// idle 추정 tick 주기(초). idleThreshold보다 촘촘해야 전이가 제때 잡힌다.
    private static let idleTickInterval: TimeInterval = 1.0

    /// 신호 하나를 탭의 추정기에 반영하고, 상태가 바뀌었으면 관측 맵을 immutable 교체 + idle 타이머를 재동기화한다.
    private func applyAgentSignal(_ signal: AgentSignal, to tabId: TabID) {
        let now = ProcessInfo.processInfo.systemUptime
        let current = estimators[tabId] ?? AgentActivityEstimator()
        let next = current.applying(signal, now: now)
        estimators[tabId] = next
        // 관측 맵은 상태가 실제로 바뀔 때만 갱신(idle은 키를 지운다) — 불필요한 SwiftUI 무효화 방지.
        if agentActivity[tabId] != next.state {
            var map = agentActivity
            if next.state == .idle { map[tabId] = nil } else { map[tabId] = next.state }
            agentActivity = map
        }
        syncIdleTimer()
    }

    /// working 추정 중인 탭이 하나라도 있으면 타이머를 켜고, 없으면 끈다.
    private func syncIdleTimer() {
        let needsTick = estimators.values.contains { $0.needsIdleTick }
        if needsTick, idleTimer == nil {
            let timer = Timer(timeInterval: Self.idleTickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickEstimators() }
            }
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
        } else if !needsTick, let timer = idleTimer {
            timer.invalidate()
            idleTimer = nil
        }
    }

    /// 모든 추정기에 tick을 넣어 출력이 멎은 working을 waiting으로 넘긴다(idle 추정).
    private func tickEstimators() {
        let now = ProcessInfo.processInfo.systemUptime
        var map = agentActivity
        var changed = false
        for (tabId, est) in estimators {
            let next = est.applying(.tick, now: now)
            guard next.state != est.state else { continue }
            estimators[tabId] = next
            if next.state == .idle { map[tabId] = nil } else { map[tabId] = next.state }
            changed = true
        }
        if changed { agentActivity = map }
        syncIdleTimer()
    }

    /// 탭이 닫힐 때 추정기·상태를 해제한다.
    private func clearAgentActivity(_ tabId: TabID) {
        estimators[tabId] = nil
        if agentActivity[tabId] != nil {
            var map = agentActivity
            map[tabId] = nil
            agentActivity = map
        }
        syncIdleTimer()
    }

    /// 탭의 현재 추정 상태(없으면 idle).
    func agentActivity(for tabId: TabID) -> AgentActivity {
        agentActivity[tabId] ?? .idle
    }

    /// 이 탭이 지금 사용자에게 보이나 — 그 뷰가 키 창에 있고, 자기 칸의 선택 탭일 때(줌이면 줌된 칸만).
    /// firstResponder가 아니라 selectedTab 기준이라 비포커스지만 보이는 분할 칸을 오판하지 않는다.
    private func isTabVisible(_ tabId: TabID) -> Bool {
        guard let term = terms[tabId], term.window?.isKeyWindow == true else { return false }
        if let zoomed = controller.zoomedPaneId {
            return controller.selectedTab(inPane: zoomed)?.id == tabId
        }
        return controller.allPaneIds.contains { controller.selectedTab(inPane: $0)?.id == tabId }
    }

    /// 신호를 오탐 필터에 태워 배지/알림을 결정한다. 보이면 배지 억제(+테두리 훅).
    private func handleSignal(_ signal: TerminalSignal, from tabId: TabID) {
        // 출력 heartbeat는 배지/알림과 무관 — 추정기만 굴리고 끝낸다(작업 중 신호).
        if case .outputHeartbeat = signal {
            applyAgentSignal(.outputHeartbeat, to: tabId)
            return
        }
        let visible = isTabVisible(tabId)
        switch signal {
        case .commandFinished(let exitCode, let duration):
            // 명령 완료는 배지 임계값과 무관하게 상태 추정(done)엔 항상 반영한다.
            applyAgentSignal(.commandFinished, to: tabId)
            // 비정상 종료(코드 != 0)는 지속시간과 무관하게 알린다. 정상+짧은 명령은 억제.
            let abnormal = (exitCode ?? 0) != 0
            guard abnormal || duration >= commandFinishedThresholdNs else { return }
            fireActivity(tabId, kind: .done, title: tabTitle(tabId), visible: visible)
        case .bell:
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastBellAt[tabId], now - last < Self.bellDebounce { return }
            lastBellAt[tabId] = now
            fireActivity(tabId, kind: .bell, title: tabTitle(tabId), visible: visible)
        case .desktopNotification(let title, let body):
            // OSC 9/777 자동 신호 — category nil로 게이트에 태운다(보이면 플래시, 안 보이면 배지+알림: 기존 동작).
            fireNotification(tabId, title: title, body: body, category: nil, kind: .notify)
        case .processExited:
            // 프로세스가 OS 레벨에서 종료 — 결정론 done(셸 통합/OSC 133 없이도 확정). 안 보이는 탭이면 배지.
            // close_surface_cb(탭 닫기)와 별개 경로다: 탭이 닫히면 didCloseTab이 추정기·배지를 정리하고,
            // 서피스가 유지되면(통합 부재 등) 이 done 테두리·배지가 유일한 종료 표식이 된다.
            applyAgentSignal(.processExited, to: tabId)
            if !visible { markBadge(tabId, kind: .done, title: tabTitle(tabId)) }
        case .outputHeartbeat:
            break // 위에서 이미 처리하고 반환 — 열거 완전성용.
        }
    }

    /// 보이면 칸 테두리 플래시, 안 보이면 배지(+인박스 이력). 벨·명령 완료 등 시스템 알림 없는 신호용.
    private func fireActivity(_ tabId: TabID, kind: AttentionKind, title: String, visible: Bool) {
        if visible { flashPane(tabId) } else { markBadge(tabId, kind: kind, title: title) }
    }

    /// 알림 발사의 단일 경로 — 순수 게이트(NotificationGate)로 배달 방식을 정하고 채널별로 실행한다.
    /// 자동 신호(OSC 9/777)는 category nil로, 명시 신호(muxa notify)는 실린 category로 들어온다.
    /// 시스템 알림 발사는 AppState에 위임(컨텍스트 부착) — 미배선 시엔 컨텍스트 없이 폴백.
    private func fireNotification(_ tabId: TabID, title: String, body: String,
                                 category: NotifyCategory?, kind: AttentionKind) {
        let delivery = NotificationGate.shouldDeliver(category: category, isVisibleToUser: isTabVisible(tabId))
        if delivery.flashPane { flashPane(tabId) }
        if delivery.systemNotification {
            // 같은 탭 연속 시스템 알림은 병합(억제) — 가장 시끄러운 채널이라 연타를 접는다. 배지·인박스는 아래에서 별도 병합.
            let (admit, next) = notifyCoalescer.admitting(tabId, now: ProcessInfo.processInfo.systemUptime)
            notifyCoalescer = next
            if admit {
                if let onNotify { onNotify(tabId, title, body) } else { NotificationService.shared.notify(title: title, body: body) }
            }
        }
        if delivery.badge { markBadge(tabId, kind: kind, title: title.isEmpty ? tabTitle(tabId) : title) }
    }

    /// 보이는 칸에 활동 테두리를 잠깐 켠다 — 3~4분할에서 "어느 칸이 울렸나"를 즉시 짚게. 일정 시간 뒤 페이드 해제.
    /// 연속 활동이면 세대값을 올려 이전 해제 타이머를 무효화(테두리가 유지된다).
    private func flashPane(_ tabId: TabID) {
        flashingTabs.insert(tabId)
        let gen = (flashSeq[tabId] ?? 0) + 1
        flashSeq[tabId] = gen
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.flashDurationNs)
            guard let self, self.flashSeq[tabId] == gen else { return }
            self.flashingTabs.remove(tabId)
            self.flashSeq[tabId] = nil
        }
    }

    /// 새 셸이 시작할 작업 디렉터리 — 원본 칸의 현재 pwd(OSC 7) > 워크스페이스 마지막 pwd > 프로젝트 기본 cwd.
    /// 원본 칸이 문서·diff 탭이거나 셸이 아직 OSC 7을 보내지 않았으면 자연스럽게 다음 순위로 떨어진다.
    private func startCwd(inPane pane: PaneID?) -> String? {
        if let pane, let tab = controller.selectedTab(inPane: pane),
           let pwd = terms[tab.id]?.pwd { return pwd }
        return lastPwd ?? cwd
    }

    /// 지금 포커스된 칸의 선택 탭이 있는 디렉터리 — 상태바 표시용.
    /// 터미널이 아닌 탭(문서·diff)에 포커스가 있으면 nil(보여줄 pwd가 없다).
    /// `pwds`(관측)와 `controller.focusedPaneId`(Bonsplit @Observable)를 읽으므로 포커스·cd 양쪽에 반응한다.
    var focusedPwd: String? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane) else { return nil }
        if let content = tabContent[tab.id], case .group = content { return nil } // 문서·diff 탭엔 pwd가 없다
        return pwds[tab.id] ?? pendingCwd[tab.id]
    }

    /// 새 터미널 탭 생성(분할 후 빈 패인 채우기·⌘T 등).
    /// `inheritingFrom`은 작업 디렉터리를 물려받을 원본 칸(분할이면 분할된 칸). 없으면 탭이 생길 칸에서 상속한다.
    @discardableResult
    func newTerminal(inPane pane: PaneID? = nil, inheritingFrom source: PaneID? = nil) -> TabID? {
        // createTab이 새 탭을 즉시 선택하므로, 원본 칸의 pwd는 생성 전에 읽는다.
        let start = startCwd(inPane: source ?? pane ?? controller.focusedPaneId)
        let id = controller.createTab(title: "터미널", icon: "terminal", inPane: pane)
        if let id {
            pendingCwd[id] = start
            regroup(id, inPane: pane ?? controller.focusedPaneId)
        }
        syncHasTabs() // 빈 상태에서 새 터미널을 열면 BonsplitView로 복귀(관측 갱신)
        persist()
        return id
    }

    // MARK: 탭 그룹핑 — 같은 종류끼리 묶기 (터미널 | 문서 | diff)
    //
    // 탭바에서 "문서는 문서끼리, diff는 diff끼리" 인접하도록 종류별 rank로 정렬 위치를 잡는다.
    // 복원 중엔 저장된 순서를 존중하므로 건너뛴다.

    /// 탭 종류 정렬 순위 — 터미널(0) < 문서(1) < HTML(2) < 코드(3) < 미디어(4) < 변경(5). 같은 순위는 생성 순서 유지.
    private func groupRank(_ content: TabContent) -> Int {
        switch content {
        case .terminal: return 0
        case .group(.documents): return 1
        case .group(.html): return 2
        case .group(.code): return 3
        case .group(.media): return 4
        case .group(.diffs): return 5
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
        let id = openInGroup(.file(FileViewTarget(path: path)))
        lastOpenedFilePath = path
        revealSeq += 1 // 익스플로러 reveal 트리거(같은 파일 재-open도 반영)
        persist()
        return id
    }

    /// 그룹 탭 상태 접근 — BonsplitWorkspaceView가 .group 탭 렌더 시 사용.
    func group(for tabId: TabID) -> TabGroupState? { groups[tabId] }

    /// ⌘W — 활성 칸의 선택 탭을 닫는다. 그룹 탭(문서/변경)이면 서브탭이 둘 이상일 땐 **선택 서브탭만** 닫고,
    /// 하나뿐이면 그룹 탭째 닫는다(closeGroupItem이 빈 그룹은 탭까지 정리). 터미널 탭은 통째로 닫는다.
    func closeActiveTab() {
        guard let pane = controller.focusedPaneId, let tab = controller.selectedTab(inPane: pane) else { return }
        if case .group = content(for: tab.id), let g = group(for: tab.id), let sel = g.selected {
            closeGroupItem(tab.id, itemId: sel.id)
        } else {
            _ = controller.closeTab(tab.id, inPane: pane)
        }
    }

    /// 이 서브탭만 남기고 같은 그룹의 나머지를 닫는다(서브탭 우클릭 "다른 서브탭 모두 닫기").
    /// 하나는 반드시 남으므로 그룹 탭 자체가 사라지지 않는다.
    func closeOtherGroupItems(_ tabId: TabID, keeping itemId: String) {
        guard let state = groups[tabId] else { return }
        for other in state.items.map(\.id) where other != itemId {
            _ = state.remove(other)
        }
        persist()
    }

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
        syncHasTabs() // 빈 상태에서 문서/diff를 열어도 메인 영역 복귀(관측 갱신)
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
        syncHasTabs() // 초기 탭 확정 → 빈 상태 게이트(showEmptyState) 해제
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

    /// 실체화된 터미널의 화면+스크롤백을 읽어(정제·상한) 별도 파일에 쓴다. 저장된 경로(없으면 nil).
    /// 부작용(서피스 리드백·파일 쓰기)은 경계 타입(TermView·ScrollbackStore)에 격리, 정제는 순수 함수.
    private func captureScrollback(from term: TermView, tabId: TabID) -> String? {
        guard let raw = term.readScreenText() else { return nil }
        return ScrollbackStore.write(ScrollbackText.sanitize(raw), for: tabId)
    }

    /// 저장 시점에 이 터미널에서 claude가 돌고 있으면 세션 인덱스로 자동 재개 바인딩을 만든다(제로설정, cmux식).
    /// 프로세스 트리(foreground→셸)로 claude 실행을 감지하고, OSC7 cwd로 마지막 세션을 해석한다. 없으면 nil.
    private func detectClaudeResume(from term: TermView, cwd: String?) -> ResumeBinding? {
        guard let cwd, let fg = term.foregroundPid, let shell = term.shellPid,
              AgentProcessDetector.agentRunning(commNames: ["claude"], from: fg, upTo: shell) else { return nil }
        return ClaudeSessionIndex.resumeBinding(forCwd: cwd)
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
                    // 현재 셸 작업 디렉터리 기록 — TermView가 살아 있으면 그 pwd, 아직 미실체화 탭이면 복원 힌트.
                    let tabCwd = terms[tid]?.pwd ?? pendingCwd[tid]
                    // 화면+스크롤백 캡처 — 실체화된 터미널이면 서피스에서 읽어 파일에 쓰고,
                    // 아직 미실체화(복원만 되고 안 연) 탭이면 이전 힌트 경로를 그대로 이어 준다(④).
                    let scrollbackFile = terms[tid].flatMap { captureScrollback(from: $0, tabId: tid) }
                        ?? restoredScrollbackFile[tid]
                    // 재개 바인딩: 지금 이 터미널에서 claude가 돌고 있으면 세션 인덱스로 자동 구성(제로설정, trusted),
                    // 아니면 훅이 등록한 바인딩(있으면). 복원 시 되살아나 배너·자동 실행으로 이어진다.
                    let resume = terms[tid].flatMap { detectClaudeResume(from: $0, cwd: tabCwd) } ?? resumeBindings[tid]
                    tabs.append(TabSnapshot(group: nil, items: [], selectedItem: 0,
                                            cwd: tabCwd, resume: resume,
                                            scrollbackFile: scrollbackFile))
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
                    if let cwd = t.cwd { pendingCwd[tid] = cwd } // 새 셸을 저장된 작업 디렉터리에서 띄우게 힌트.
                    if let resume = t.resume { registerResumeBinding(resume, for: tid) } // 재개 바인딩 복구(+배너 표시). 실행은 게이트가.
                    // 신뢰 재개(claude 자동)는 곧 claude가 화면을 덮으므로 죽은 스크롤백 리플레이를 건너뛴다(잔상·중복 방지).
                    if let sf = t.scrollbackFile, t.resume?.trusted != true { restoredScrollbackFile[tid] = sf } // 새 셸에 스크롤백 파일 env 주입 힌트(④).
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
