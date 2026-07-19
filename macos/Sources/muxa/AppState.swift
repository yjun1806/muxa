import AppKit
import Bonsplit
import Foundation
import GhosttyKit
import Observation

/// 앱 전역 상태 + 영속. 워크스페이스(사이드바) ⊃ 프로젝트(상단 탭) ⊃ 터미널 탭(Bonsplit).
/// 프로젝트마다 TerminalStore(Bonsplit 컨트롤러) 하나를 lazy 생성·유지한다.
///
/// 재시작 시 워크스페이스·프로젝트·사이드바 모드 + 프로젝트별 분할 트리가 복원된다.
/// PTY는 프로세스라 복원 불가 → 각 탭은 프로젝트 cwd에서 새 셸로 시작한다.
@MainActor
@Observable
final class AppState {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeId: String = "" // 활성 워크스페이스
    private(set) var sidebarMode: SidebarMode = .expanded

    /// 지금 펼쳐져 있는 워크스페이스 id들(사이드바 2단 트리) — **유일한 진실**. 각 워크스페이스는
    /// 독립적으로 여닫힌다(아코디언 아님 — `SidebarTree.toggled`는 하나만 건드린다). 활성 워크스페이스도
    /// 여기에 들어간다(전환·생성·로드 시 삽입) — 포커스한 곳은 프로젝트가 보여야 하기 때문.
    private(set) var expandedWorkspaces: Set<String> = []

    /// **접어 둔** 에이전트 목록의 프로젝트 id들 — 기본이 펼침이라 접은 것만 기억한다
    /// (새 프로젝트·구 저장분은 집합에 없음 = 펼침, 마이그레이션 불필요). 프로젝트 전환 시 자동 펼침은
    /// 여기서 제거로 구현된다(`expandAgentList`).
    private(set) var collapsedAgentLists: Set<String> = []

    /// 백그라운드 활동(●)이 있는 프로젝트 id들(A). 사이드바 프로젝트 행이 관측해 상태 글리프를 그린다.
    private(set) var badgedProjects: Set<String> = []

    /// 워크트리 폴더가 사라진 프로젝트 id들 — **닫지 않고 배지("묘비")로만 표시**한다(사용자가 직접 정리). 판정은
    /// 순수(`DeadWorktree`), 갱신은 `reconcileDeadWorktrees`. 디스크가 진실인 런타임 파생 상태라 영속 모델에 안 넣는다.
    private(set) var deadWorktreeProjectIds: Set<String> = []

    /// 분리 창 목록(SSOT). **메인 창은 여기 없다** — 어느 창에도 없는 프로젝트가 메인 소유다(D29, 여집합).
    /// 조회·이동·정리는 전부 `AppState+Windows`에.
    private(set) var projectWindows: [ProjectWindow] = []

    /// `projectWindows`의 쓰기 통로. Swift의 `private(set)`은 **파일을 넘지 못해** 확장 파일
    /// (`AppState+Windows.swift`)에서 직접 대입할 수 없다 — 문 하나만 열어 둔다.
    func setProjectWindows(_ next: [ProjectWindow]) { projectWindows = next }

    /// 실물 창 경계(NSWindow reconcile·raise). 앱 델리게이트가 시작 시 꽂는다 — 테스트·순수 경로에선 nil.
    /// 상태가 창을 **직접** 만들지 않고 이 경계에만 위임한다(부작용 격리).
    @ObservationIgnored weak var windowHost: WindowHost?

    /// 분리 창 프레임 저장을 미뤄 두는 예약(디바운스 — `saveDebounced`). 새 이동이 오면 취소·재예약된다.
    @ObservationIgnored private var frameSaveWork: DispatchWorkItem?
    private static let frameSaveDelay: TimeInterval = 0.5

    /// 아직 모델에 반영하지 않은 창 프레임(드래그 중) — **관측 밖**이라 뷰를 흔들지 않는다.
    /// `save()` 직전에 한 번만 `projectWindows`에 병합한다(`AppState+Windows.recordFrame`).
    @ObservationIgnored var pendingFrames: [WindowID: FrameSnapshot] = [:]

    /// 쌓아 둔 프레임을 모델에 병합한다 — 저장 직전에만 부른다(재대입 = 뷰 무효화).
    func flushPendingFrames() {
        guard !pendingFrames.isEmpty else { return }
        var next = projectWindows
        for idx in next.indices {
            if let frame = pendingFrames[next[idx].id] { next[idx].frame = frame }
        }
        pendingFrames.removeAll()
        projectWindows = next
    }

    /// 모든 워크스페이스의 프로젝트 id — `WindowLayout.normalize`의 "아는 프로젝트" 목록.
    var allProjectIds: [String] { workspaces.flatMap { $0.projects.map(\.id) } }

    /// 워크트리 피커 요청(원샷) — 사이드바 워크스페이스 행의 `+`가 올리고, ContentView(시트 소유자)가 소비한다.
    /// **뷰가 아니라 상태가 요청을 소유하는 이유**: `+`는 hover에서만 존재하는 버튼이라 시트를 그 행에 달면
    /// 마우스가 떠나 행이 사라질 때 시트도 함께 죽는다(`serviceAddRequested`와 같은 패턴).
    var worktreePickerRequested = false

    /// 놓친 주의 이력(알림 인박스). 배지가 붙는 순간마다 한 건씩 쌓인다 — 배지는 "지금 상태",
    /// 이건 "자리 비웠다 돌아왔을 때의 복구 동선". 상단바 벨 팝오버가 관측해 렌더한다.
    let attention = AttentionLog()

    /// 서비스(장수 프로세스) 상태 관측 — 접혀 있어도 tmux에 물어 돈다. 앱 전체에 하나(Service.swift).
    let serviceMonitor = ServiceMonitor()
    /// 워크트리 감지(경계) — 각 워크스페이스 repo의 공통 `.git`을 FSEvents로 감시한다. 승격은 안 하고
    /// 감지만 값으로 노출한다(D31). "추가?" 제안·baseline은 이 타입(AppState)이 소유한다.
    let worktreeMonitor = WorktreeMonitor()

    /// 서비스 도크(하단 오버레이) 표시 상태와 선택된 서비스.
    /// 오버레이인 이유는 `ServiceDock` 주석과 ARCHITECTURE §4.7(D19)에 한 번만 적는다.
    var showServiceDock = false
    /// 선택된 상세 대상 — 서비스·스크립트·일회용이 **한 필드를 공유**한다(전부 UUID라 충돌 없음).
    var selectedServiceId: String?
    /// 지금 보고 있는 도크 탭(서비스/스크립트/일회용). 순간 내비게이션이라 비영속 — 진입점(칩·⌘K)이
    /// 항상 명시하고, ⌘J(중립 토글)만 직전 탭을 잇는다.
    var dockTab: DockTab = .services
    /// ⌘K "일회용 명령 실행" 원샷 — 도크가 일회용 탭 입력창에 포커스를 주고 내린다.
    var oneOffFocusRequested = false

    /// 도크가 그리는 프로젝트 — 도크를 **연 시점에** 못 박는다(nil = 메인의 활성 프로젝트).
    /// 분리 창의 서비스도 로그는 메인 도크에서 보므로(도크는 v1에서 메인 전용 — §6), 도크 스코프가
    /// 메인의 활성 프로젝트로 고정돼 있으면 사용자가 클릭한 서비스가 아니라 **엉뚱한 프로젝트의 로그**가 뜬다.
    private(set) var dockProjectId: String?

    /// 서비스 도크에서 **펼쳐 둔 타 워크스페이스** 스코프들(id). 현재 워크스페이스는 늘 펼침이라 여기 없어도 된다.
    /// 기본은 접힘 — 다른 워크스페이스는 한 줄(개수+롤업 상태)로 조용히 두고, 필요할 때만 펼친다. 세션 내 상태(비영속).
    private(set) var expandedServiceScopes: Set<String> = []

    func toggleServiceScope(_ id: String) {
        if expandedServiceScopes.contains(id) { expandedServiceScopes.remove(id) }
        else { expandedServiceScopes.insert(id) }
    }

    /// 도구 패널 표시 상태(B). 재시작 시 마지막 열림/닫힘을 복원(Persisted에 저장) — 매번 다시 열 필요 없이.
    /// 상단바 토글 버튼·단축키(⌘⇧E/⌘⇧G)·알림이 이 상태를 연다.
    var showExplorer = false
    var showGitPanel = false
    /// 인스펙터 탭 — 익스플로러·Git·설정·알림이 **한 슬롯**을 공유한다(하나만 보임, 통일 폭). 서비스 서랍은 별개.
    var showSettings = false
    var showAttention = false
    /// **인스펙터 폭** — 어느 탭이든 공유(통일). 좌측 경계 드래그로 리사이즈·영속(`explorerWidth` 필드 재사용).
    /// 드래그 중엔 ResizablePanel 로컬 상태로만 움직이고, 손 뗀 순간에만 여기로 커밋해 저장한다.
    private(set) var explorerWidth: CGFloat = 340
    /// 서비스 서랍 폭 — 탐색기·Git과 같은 좌측 경계 드래그 리사이즈·영속. 좌(목록)+우(터미널)를 나란히
    /// 담으므로 로그가 읽히려면 하한이 넓다.
    private(set) var serviceDockWidth: CGFloat = AppState.defaultServiceDockWidth
    /// 서비스 도크 안 **목록 칼럼** 폭 — [좌: 목록 | 우: 터미널] 분할의 왼쪽. 세션 내 조절(비영속).
    /// 탭 바가 도크 전폭으로 올라가 목록 열엔 탭이 없으므로, 목록은 좁게(사이드바처럼) 두고 상세를 넓게 쓴다.
    private(set) var serviceListWidth: CGFloat = 240

    static let defaultPanelWidth: CGFloat = 280
    static let panelWidthRange: ClosedRange<CGFloat> = 180 ... 720
    // Git 패널은 브랜치 헤더·3분할 피커·커밋 박스가 들어가 익스플로러(파일 트리)보다 최소 너비가 크다.
    static let defaultGitPanelWidth: CGFloat = 320
    static let gitPanelWidthRange: ClosedRange<CGFloat> = 300 ... 720
    // 서비스 서랍은 좌(목록)+우(터미널)를 나란히 담아 좁으면 터미널이 안 읽힌다 — Git보다 하한·기본을 키운다.
    static let defaultServiceDockWidth: CGFloat = 560
    static let serviceDockWidthRange: ClosedRange<CGFloat> = 420 ... 900
    static let serviceListWidthRange: ClosedRange<CGFloat> = 150 ... 360
    static func clampPanelWidth(_ w: CGFloat) -> CGFloat { clamp(w, to: panelWidthRange) }
    static func clampGitPanelWidth(_ w: CGFloat) -> CGFloat { clamp(w, to: gitPanelWidthRange) }
    static func clampServiceDockWidth(_ w: CGFloat) -> CGFloat { clamp(w, to: serviceDockWidthRange) }
    private static func clamp(_ w: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(w, range.lowerBound), range.upperBound)
    }

    func setExplorerWidth(_ w: CGFloat, persist: Bool = true) {
        explorerWidth = Self.clampPanelWidth(w)
        if persist { save() }
    }

    func setServiceDockWidth(_ w: CGFloat, persist: Bool = true) {
        serviceDockWidth = Self.clampServiceDockWidth(w)
        if persist { save() }
    }

    func setServiceListWidth(_ w: CGFloat) {
        serviceListWidth = Self.clamp(w, to: Self.serviceListWidthRange)
    }

    // MARK: - 인스펙터(단일 슬롯 탭 — 익스플로러·Git·설정·알림)

    /// 지금 열린 인스펙터 탭 — bool들의 상호배타를 하나의 값으로 읽는다(닫혔으면 nil). 설정은 탭이 아니다.
    var inspectorTab: InspectorTab? {
        if showExplorer { return .explorer }
        if showGitPanel { return .git }
        if showAttention { return .attention }
        return nil
    }

    /// 인스펙터 열기 버튼이 다시 열 때 돌아갈 마지막 탭(닫아도 기억). 상단바 "사이드 패널" 버튼용.
    @ObservationIgnored private(set) var lastInspectorTab: InspectorTab = .explorer

    /// 닫혀 있으면 마지막 탭으로 열고, 열려 있으면 닫는다 — 상단바 사이드 패널 버튼.
    func toggleInspector() { setInspector(inspectorTab == nil ? lastInspectorTab : nil) }
    /// 탭 선택 — 같은 탭을 다시 누르면 닫는다(토글). 항상 하나만 켠다.
    func selectInspector(_ tab: InspectorTab) { setInspector(inspectorTab == tab ? nil : tab) }
    /// 특정 탭을 **강제로 연다**(토글 아님) — 알림·검토 클릭 같은 "이걸 보여줘" 동선.
    func openInspector(_ tab: InspectorTab) { setInspector(tab) }
    func closeInspector() { setInspector(nil) }
    /// 설정 진입 시 "이 섹션 보여줘" 요청 — 사용량 팝오버 톱니 등 외부 동선이 싣는다.
    /// 패널이 스크롤·강조에 한 번 쓰고 nil로 비운다(재요청이 같은 섹션이어도 다시 트리거되게). 세션 전용(비영속).
    var settingsFocus: SettingsSection?

    /// 설정 패널 토글 — **인스펙터와 같은 우측 슬롯**을 쓰므로 열면 인스펙터를 닫는다(스택 방지).
    func toggleSettings() {
        let open = !showSettings
        showExplorer = false; showGitPanel = false; showAttention = false
        showSettings = open
        saveDebounced()
    }

    /// 설정을 열고 특정 섹션으로 스크롤·강조한다("여기 설정 보여줘" 동선). 이미 열려 있어도 focus만 다시 실어
    /// 재-스크롤/플래시를 트리거한다(패널이 `settingsFocus`를 소비한다).
    func openSettings(focus: SettingsSection) {
        showExplorer = false; showGitPanel = false; showAttention = false
        showSettings = true
        settingsFocus = focus
        saveDebounced()
    }

    private func setInspector(_ tab: InspectorTab?) {
        if let tab { lastInspectorTab = tab }
        showSettings = false // 인스펙터를 열면 설정 패널을 닫는다(우측 슬롯은 하나)
        showExplorer = tab == .explorer
        showGitPanel = tab == .git
        showAttention = tab == .attention
        // 탭 전환마다 동기 디스크 I/O(save)를 피한다 — 그게 클릭이 가끔 씹히던 원인(메인스레드 히치).
        // 디바운스로 합쳐 저장한다(빠른 연속 전환은 마지막 한 번만 기록).
        saveDebounced()
    }

    /// 알림 배지 수 = 안 읽은 이력 + 처리 안 한 워크트리 제안. **상단바 벨과 인스펙터 알림 탭이 공유**한다
    /// (같은 계산을 두 곳에 복붙하지 않는다). 경로 유니크로 세어 공유 repo의 이중 카운트를 막는다.
    var attentionBadgeCount: Int {
        let offers = Set(workspaces.flatMap { worktreeOffers(for: $0).map(\.path) }).count
        return attention.unreadCount + offers
    }

    /// ⌘K 빠른 전환기(명령 팔레트) 표시 상태 — 세션 영속 대상 아님. 단축키가 토글한다.
    var showQuickSwitch = false

    /// 키바인딩 재정의 진단(충돌·예약키 침범·파싱 실패). main이 키맵을 (재)빌드할 때마다 채운다.
    /// 지금은 로그가 1차 표면이고 이 배열은 UI 노출용 예비 — 관측 가능하게 값으로만 둔다(세션 영속 대상 아님).
    var keymapDiagnostics: [KeymapDiagnostic] = []

    /// Claude 훅 설치 상태(파일 기준). 시작 시·설치 직후 갱신한다.
    private(set) var hookInstall: HookInstallState = .notInstalled
    /// 훅 신호를 이 세션에서 한 번이라도 받았는가 — "설치됨"을 "동작 중"으로 승격시키는 유일한 근거.
    /// settings.json에 썼다는 것과 훅이 실제로 발화한다는 것은 다르다(경로·권한·버전).
    private(set) var hookSignalSeen = false

    /// UI에 보여줄 훅 상태 — 파일 상태 + 실제 신호 수신을 합친 최종 값.
    ///
    /// **신호가 실제로 오면 그게 진실이다**(파일이 뭐라 하든). 훅 command 형식이 우리가 쓰는 것과 달라도
    /// (손으로 넣었거나 옛 버전이 심었거나) 신호가 도착한다면 그건 동작하는 것이다 — "미설치"라고 말하면 거짓말이다.
    var hookStatus: HookInstallState {
        if hookSignalSeen { return .verified }
        return hookInstall
    }

    @ObservationIgnored private let app: ghostty_app_t
    /// muxa 설정(`~/.config/muxa/config`) — 시작 시 로드해 주입하고, 파일 저장 시 ConfigWatcher가
    /// `applyConfig`로 라이브 갱신한다(재시작 불필요). 기본 사이드바 모드·완료 배지 임계 등. (ARCHITECTURE 4.6)
    @ObservationIgnored private(set) var config: MuxaConfig
    /// 프로젝트 id → TerminalStore. 프로젝트가 독립 분할 레이아웃 하나를 소유한다.
    @ObservationIgnored private var stores: [String: TerminalStore] = [:]
    /// 프로젝트 id → 통합 레이아웃 스냅샷(재시작 복원용). 아직 안 연 프로젝트 것도 보존한다.
    @ObservationIgnored private var savedLayouts: [String: PaneSnapshot] = [:]

    /// 훅 알림 리스너(Unix 소켓). 앱 상태가 소유하고, 수신 시 tabId→store로 라우팅한다.
    @ObservationIgnored private let notifyServer = NotifyServer()

    init(app: ghostty_app_t, config: MuxaConfig = .defaults) {
        self.app = app
        self.config = config
        // 설정의 사이드바 기본 모드를 초기값으로. 저장된 세션이 있으면 load()가 사용자의 마지막 선택으로 덮는다.
        self.sidebarMode = config.sidebarMode
        // 공통 .git이 움직이면(cc가 git worktree add/remove) ① 사라진 폴더 배지 재판정(닫지 않고 표시만)
        // ② muxa 세션이 들어가 있는 새 워크트리 자동 승격(D31 보완).
        worktreeMonitor.onChange = { [weak self] in
            self?.reconcileDeadWorktrees()
            self?.autoImportWorktrees()
        }
    }

    /// 설정 파일 저장이 감지됐을 때 새 설정을 반영한다(ConfigWatcher → AppDelegate가 호출). (ARCHITECTURE 4.6)
    /// 라이브 반영 대상은 "런타임 동작값"뿐 — 완료 배지 임계는 이미 생성된 스토어에도 전파한다.
    /// confirm_quit은 종료 시점에 config를 읽으므로 값 교체만으로 즉시 유효하다.
    /// sidebar_mode·default_workspace_path는 "초기 기본값" 성격이라 라이브 반영 제외 —
    /// 세션에서 사용자가 토글/열어둔 현재 상태를 config 저장이 되돌리지 않게 한다(세션 우선순위 유지).
    func applyConfig(_ newConfig: MuxaConfig) {
        config = newConfig
        let ns = newConfig.commandFinishedThresholdNs
        for store in stores.values {
            store.updateCommandFinishedThreshold(ns)
            store.updateAgentResumeMode(newConfig.agentResume) // 재개 승인 게이트도 실행 중 스토어에 전파(D2)
        }
    }

    /// 탭 스타일 설정(`TabStyleSettings`)이 바뀌면 **열린 모든 칸**에 라이브로 민다.
    /// `BonsplitController`가 @Observable이고 뷰가 `configuration.appearance`를 읽으므로,
    /// appearance를 갈아끼우면 탭바가 즉시 새 스타일로 다시 그려진다(재시작 불필요).
    func reapplyTabAppearance() {
        for store in stores.values {
            var appearance = store.controller.configuration.appearance
            BonsplitChrome.applyTabStyle(TabStyleSettings.shared, to: &appearance)
            store.controller.configuration.appearance = appearance
        }
    }

    /// 훅 알림 리스너를 켜고 라우팅 콜백을 건다. AppDelegate가 앱 시작 시 1회 호출.
    func startNotifyServer() {
        notifyServer.onMessage = { [weak self] msg in
            MainActor.assumeIsolated { self?.routeNotify(msg) }
        }
        notifyServer.onHook = { [weak self] msg in
            MainActor.assumeIsolated { self?.routeHook(msg) }
        }
        notifyServer.start()
        refreshHookInstallState()
    }

    /// 파일 기준 훅 설치 상태를 다시 읽는다(시작 시·설치/제거 직후).
    func refreshHookInstallState() {
        hookInstall = ClaudeHookInstaller.installState()
    }

    /// 사용자 동작으로 훅을 설치한다 — `~/.claude/settings.json`을 고치는 일이라 **자동 실행하지 않는다**.
    /// 실패는 상태로 표면화한다(조용히 삼키면 "왜 알림이 안 오지"의 원인을 영영 모른다).
    func installClaudeHooks() {
        do {
            try ClaudeHookInstaller.install()
            hookInstall = .installed
        } catch {
            hookInstall = .failed(error.localizedDescription)
            attention.recordSystem(title: "Claude 훅 설치 실패 — \(error.localizedDescription)")
        }
    }

    /// muxa 훅만 제거한다(사용자 훅은 남는다).
    func uninstallClaudeHooks() {
        do {
            try ClaudeHookInstaller.uninstall()
            hookInstall = .notInstalled
            hookSignalSeen = false
        } catch {
            hookInstall = .failed(error.localizedDescription)
        }
    }

    /// 훅 원본 payload를 tabId 소유 store로 라우팅한다(routeNotify와 같은 순회 규칙).
    /// 해석·배달은 소유 store가 한다 — AppState는 배관일 뿐이다.
    private func routeHook(_ msg: HookMessage) {
        guard let uuid = UUID(uuidString: msg.tabId) else { return }
        let tabId = TabID(uuid: uuid)
        hookSignalSeen = true // 훅이 실제로 도착했다 — 설치가 "검증됨"으로 승격된다
        for store in stores.values {
            if store.deliverHook(tabId: tabId, event: msg.event, payload: msg.payload) { break }
        }
    }

    /// 훅 메시지를 tabId 소유 store로 라우팅한다. 어느 store가 그 탭을 가졌는지는 순회로 찾는다
    /// (stores는 프로젝트별이고 탭 수가 적어 순회로 충분). 소유 store가 배지·알림을 결정한다.
    private func routeNotify(_ msg: NotifyMessage) {
        guard let uuid = UUID(uuidString: msg.tabId) else { return }
        let tabId = TabID(uuid: uuid)
        for store in stores.values {
            if store.deliverNotify(tabId: tabId, state: msg.state, title: msg.title,
                                   body: msg.body, category: msg.category, resume: msg.resume) { break }
        }
    }

    // MARK: 알림 → 원클릭 검토 동선 (배지·시스템 알림 클릭)

    /// 스토어(프로젝트)가 요청한 데스크톱 알림에 라우팅 컨텍스트를 붙여 발사한다.
    /// 워크스페이스 id는 프로젝트 소속으로 파생(단일 진실 원천) — 스토어는 몰라도 된다.
    private func emitNotification(projectId: String, tabId: TabID, title: String, body: String) {
        let workspaceId = workspace(containing: projectId)?.id ?? ""
        let context = NotifyContext(workspaceId: workspaceId, projectId: projectId, tabId: tabId.uuid.uuidString)
        NotificationService.shared.notify(title: title, body: body, context: context)
    }

    /// 배지가 붙는 순간 인박스 이력에 한 건 기록한다. 워크스페이스 id는 프로젝트 소속으로 파생(단일 진실 원천).
    private func recordAttention(projectId: String, tabId: TabID, kind: AttentionKind, title: String) {
        let workspaceId = workspace(containing: projectId)?.id ?? ""
        attention.record(workspaceId: workspaceId, projectId: projectId,
                         tabId: tabId.uuid.uuidString, kind: kind, title: title)
    }

    /// 키맵 재정의 진단을 노출값에 반영하고, 알림 인박스에 시스템 경고로 표면화한다(시작·라이브 리로드 공통 경로).
    /// main의 os_log는 개발자 표면, 인박스는 사용자 표면 — "왜 내 단축키가 안 먹지"를 상단바 벨에서 확인하게 한다.
    /// 시스템 항목은 탭에 안 묶인 전역 항목이라 클릭 점프 대상이 없다(recordSystem이 dedup·전역 컨텍스트 처리).
    func surfaceKeymapDiagnostics(_ diagnostics: [KeymapDiagnostic]) {
        keymapDiagnostics = diagnostics
        for diagnostic in diagnostics {
            attention.recordSystem(title: diagnostic.message)
        }
    }

    /// 알림 권한이 거부된 상태를 인박스에 표면화한다(dedup은 AttentionLog가 한다 — 활성화마다 불려도 1건).
    /// 이 앱의 핵심 가치가 "에이전트가 기다리면 알려준다"인데, 거부는 조용한 Dock 바운스로 끝나 사용자가
    /// 고장으로 오해한다. 켜는 방법까지 문장에 담는다.
    func surfaceNotificationsDisabled() {
        attention.recordSystem(title: "알림이 꺼져 있습니다 — 시스템 설정 > 알림에서 \(AppInfo.name)을(를) 허용하세요.")
    }

    /// 인박스 항목 클릭 → 그 칸으로 점프(원클릭 검토 동선 재사용). 소속이 사라진 항목이면 무동작.
    /// 시스템 항목(빈 컨텍스트)도 revealActivity가 소속 프로젝트를 못 찾아 안전하게 무동작한다.
    func revealAttention(_ entry: AttentionEntry) {
        // 인박스 항목 클릭 = 그 칸으로 점프. Git 탭을 자동으로 열지 않는다(단일 슬롯이라 열면 인박스가
        // 사라지고, onClose가 다시 닫아 충돌한다 — diff는 어차피 탭으로 열린다).
        revealActivity(projectId: entry.projectId, tabId: entry.tabId, openGitPanel: false)
    }

    /// 인박스 항목 위치 라벨 — "워크스페이스 · 프로젝트". 소속을 못 찾으면 빈 문자열.
    func attentionLocationLabel(projectId: String) -> String {
        guard let ws = workspace(containing: projectId),
              let p = ws.projects.first(where: { $0.id == projectId }) else { return "" }
        return "\(ws.name) · \(p.name)"
    }

    /// 배지·시스템 알림 클릭의 공통 착지점 — 대상 프로젝트로 이동 + Git 패널 오픈 + (있으면) 그 탭 선택 + 앱 활성화.
    /// 배지 클릭·알림 클릭이 이 한 메서드를 공유한다("원클릭 검토" 동선의 단일 구현).
    ///
    /// **배지 해제·탭 선택은 소유 창과 무관하게 언제나 먼저 한다**(명세 §5.3) — 창 분기를 진입부에서
    /// early-return으로 하면 정작 주의를 요구한 그 탭이 선택되지 않는다. 창은 "좌표를 어디에 반영할지"만 가른다.
    /// `openGitPanel` — 명시적 "검토" 동선(시스템 알림·알림 인박스 클릭)만 true. 사이드바 내비게이션은
    /// false로 불러 **이동만 하고 git 패널을 강제로 열지 않는다**(배지가 잦으면 이동마다 git이 열려 성가시다).
    func revealActivity(projectId: String, tabId: String? = nil, openGitPanel: Bool = true) {
        guard let ws = workspace(containing: projectId) else { return }
        clearBadge(projectId)
        // **서비스는 탭이 아니다.** 죽음 알림은 tabId 자리에 서비스 id를 담는데(startServices의 onExit),
        // 서비스는 탭 트리 밖이라 그 id로 찾을 탭이 없다 — 그대로 흘려보내면 프로젝트만 이동하고
        // Git 패널이 열려 정작 봐야 할 로그(도크)는 안 뜬다. 서비스면 서비스 동선으로 보낸다.
        if let tabId, let service = locateService(tabId, in: workspaces) {
            revealService(service)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // **스크립트도 탭이 아니다** — 실패 알림은 tabId 자리에 스크립트 id를 담는다(onScriptsPoll).
        // 로그는 서비스 도크의 스크립트 상세에 있다(서비스와 같은 동선·같은 이유).
        if let tabId, allLocatedScripts.contains(where: { $0.id == tabId }) {
            revealScript(scriptId: tabId)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let tabId, let uuid = UUID(uuidString: tabId), let store = stores[projectId] {
            store.revealTab(TabID(uuid: uuid))
        }
        guard !routeToOwner(projectId) else { return } // 분리 창이면 그 창만 앞으로 + 그 창의 좌표만
        setActiveId(ws.id)        // 대상 워크스페이스로
        setActiveProject(projectId) // 그 안의 프로젝트로
        if openGitPanel { openInspector(.git) } // 명시적 검토 동선에서만 Git 탭 자동 오픈
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: ⌘K 빠른 전환기 (계층 5단 퍼지 탐색 — "나를 기다리는 세션으로 즉시 점프")

    func toggleQuickSwitch() { showQuickSwitch.toggle() }

    /// 전환기가 탐색·정렬할 전체 항목을 계층 순서(워크스페이스›프로젝트›탭›서브탭)로 만든다.
    /// 열린 프로젝트(store 존재)만 탭·서브탭을 편다 — 배지는 실행 중 스토어에서만 생기므로 누락 없음.
    /// 대기 우선 정렬은 랭킹(QuickSwitchRanker)이 waiting 플래그로 처리한다.
    func quickSwitchItems() -> [QuickSwitchItem] {
        var items: [QuickSwitchItem] = []
        for ws in workspaces {
            // 대기 판정을 **사이드바와 한 출처로**(projectStatus/workspaceStatus == .attention) — 배지뿐 아니라
            // 보이는 대기 탭·죽은 서비스도 포함해야 "사이드바는 호박인데 ⌘K엔 표식 없음"(C3)이 안 생긴다.
            items.append(QuickSwitchItem(
                id: "ws:\(ws.id)", kind: .workspace, title: ws.name, subtitle: "워크스페이스",
                icon: "square.stack", waiting: workspaceStatus(ws) == .attention,
                workspaceId: ws.id, projectId: nil, tabId: nil, subItemId: nil))
            for project in ws.projects {
                items.append(QuickSwitchItem(
                    id: "pj:\(project.id)", kind: .project, title: project.name, subtitle: ws.name,
                    icon: "folder", waiting: projectStatus(project.id) == .attention,
                    workspaceId: ws.id, projectId: project.id, tabId: nil, subItemId: nil))
                guard let store = stores[project.id] else { continue }
                let loc = "\(ws.name) · \(project.name)"
                for qt in store.quickSwitchTabs() {
                    let tabTitle = qt.title.isEmpty ? TerminalStore.defaultTerminalTitle : qt.title
                    let uuid = qt.tabId.uuid.uuidString
                    items.append(QuickSwitchItem(
                        id: "tab:\(uuid)", kind: .tab, title: tabTitle, subtitle: loc,
                        icon: qt.icon ?? "terminal",
                        waiting: qt.badged || store.agentActivity(for: qt.tabId) == .waiting,
                        workspaceId: ws.id, projectId: project.id, tabId: qt.tabId, subItemId: nil))
                    for sub in qt.subItems {
                        items.append(QuickSwitchItem(
                            id: "sub:\(uuid):\(sub.id)", kind: .subtab, title: sub.title,
                            subtitle: "\(loc) · \(tabTitle)", icon: sub.icon, waiting: false,
                            workspaceId: ws.id, projectId: project.id, tabId: qt.tabId, subItemId: sub.id))
                    }
                }
            }
        }
        // 점프 대상 뒤에 실행 명령을 섞는다 — 같은 FuzzyMatch/랭킹을 타고, 대기(배지) 우선 정렬은 유지된다.
        items.append(contentsOf: QuickCommandCatalog.items)
        return items
    }

    /// 전환기 항목 실행 — 명령 항목이면 KeymapAction을 실행(키맵과 같은 경로)하고, 점프 항목이면 좌표로 라우팅한다.
    /// 어느 쪽이든 먼저 팔레트를 닫는다(dismissOnRun). 점프는 원클릭 라우팅을 재사용하고 git 패널은 열지 않는다.
    func quickJump(_ item: QuickSwitchItem) {
        showQuickSwitch = false
        if let action = item.action {
            perform(action) // 명령 항목 — main.swift 키 모니터와 공유하는 실행 경로.
            return
        }
        // 탭·서브탭 선택은 소유 창과 무관하게 먼저(§5.3) — 그 다음에 좌표를 어느 창에 반영할지 가른다.
        if let projectId = item.projectId, let tabId = item.tabId, let store = stores[projectId] {
            store.revealTab(tabId)
            if let subItemId = item.subItemId { store.selectGroupItem(tabId, itemId: subItemId) }
        }
        if let projectId = item.projectId, routeToOwner(projectId) { return }
        setActiveId(item.workspaceId)
        if let projectId = item.projectId { setActiveProject(projectId) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 크롬 동작 실행 (키맵·팔레트 공유 단일 진실 원천 — ARCHITECTURE 7 라우팅)

    /// ∞ 닫기 확인 배너가 떠 있는 칸의 키를 배너 결정으로 소비한다 — ⌘W=완전 종료·⌘B=백그라운드 유지·⌘C/esc=취소.
    ///
    /// **keymap.resolve보다 앞서** 불려야 한다: 안 그러면 ⌘W가 `.closeTab`으로 잡혀 "완전 종료" 대신
    /// 또 확인을 돌린다. 배너가 없으면 false를 돌려 기존 단축키·터미널 입력으로 흘려보낸다(평소 흐름 불변).
    /// 배너가 떠 있는 활성(선택+포커스) 칸에만 적용 — 다른 칸의 배너는 클릭으로 결정한다.
    func closeConfirmShortcut(keyCode: Int, characters: String?,
                             flags: NSEvent.ModifierFlags, in windowId: WindowID) -> Bool {
        guard let store = store(ownedBy: windowId),
              let pane = store.controller.focusedPaneId,
              let tab = store.controller.selectedTab(inPane: pane),
              store.closeConfirmation(for: tab.id) != nil else { return false }
        if keyCode == 53 { store.cancelClose(tab.id); return true } // esc — ⌘ 없이도 취소
        guard flags.contains(.command) else { return false } // ⌘ 없는 다른 키는 터미널로 흘려보낸다
        switch characters?.lowercased() {
        case "w": store.confirmCloseKilling(tab.id); return true
        case "b": store.confirmCloseKeeping(tab.id); return true
        case "c": store.cancelClose(tab.id); return true
        default: return false
        }
    }

    /// KeymapAction 하나를 실행한다 — main.swift 로컬 키 모니터와 ⌘K 팔레트가 공유하는 실행 경로.
    /// 실행됐으면(=소비) true. 활성 스토어가 필요한 동작(⌘T/⌘D/⌘W/⌘F 등)은 스토어가 없으면 무동작(false).
    /// 부작용(스토어·창 조작)은 이 메서드와 아래 store 헬퍼에만 격리한다.
    ///
    /// `windowId` = 키를 친 창. 스토어 대상 동작은 **그 창이 소유한** 스토어에만 적용하고,
    /// 크로스윈도우 동작(워크스페이스 전환·⌘K·⌘⇧A)은 사이드바·팔레트가 있는 메인 창을 먼저 앞으로 올린다.
    /// (팔레트가 부르는 경로는 언제나 메인 — 기본값.)
    @discardableResult
    func perform(_ action: KeymapAction, in windowId: WindowID = .main) -> Bool {
        switch action {
        case .switchWorkspace(let n):
            guard workspaces.indices.contains(n - 1) else { return false }
            raiseMainIfNeeded(from: windowId)
            setActiveId(workspaces[n - 1].id)
            return true
        case .cycleProject(let forward):
            // 돌 곳이 없어도 **키는 삼킨다** — 매치된 단축키를 통과시키면 ⌘⇧[ 가 터미널에 문자로 꽂힌다.
            // "할 일이 없다"와 "이 키는 내 것이 아니다"는 다르다.
            cycleProject(forward: forward, in: windowId)
            return true
        case .toggleExplorer:
            togglePanel(explorer: true, in: windowId); return true
        case .toggleGitPanel:
            togglePanel(explorer: false, in: windowId); return true
        case .jumpToNextWaiting:
            raiseMainIfNeeded(from: windowId)
            jumpToNextWaiting(); return true
        case .quickSwitch:
            raiseMainIfNeeded(from: windowId)
            toggleQuickSwitch(); return true
        case .toggleServiceDock:
            // 도크는 v1에서 메인 창 전용이다(§6) — 분리 창에서 눌렀으면 도크가 뜨는 창을 먼저 앞으로 올린다.
            // 안 그러면 보이지도 않는 메인에 도크가 열리고, 사용자는 ⌘J가 죽은 줄 안다.
            raiseMainIfNeeded(from: windowId)
            if showServiceDock { closeServiceDock() } else { openServiceDock(serviceId: nil) }
            return true
        case .separateProject:
            // 메인이 보고 있는 프로젝트를 새 창으로 — 이미 분리 창에서 눌렀다면 분리할 것이 없다.
            guard windowId.isMain, let projectId = activeProject?.id else { return false }
            separateProject(projectId)
            return true
        case .addScript:
            // 등록할 프로젝트가 없으면 무동작 — 시트(대상 프로젝트에 등록)가 빈 대상에 뜨면 안 된다.
            // 시트 호스트는 메인 창의 StatusBar다(칩은 등록 0개면 숨어 첫 등록을 못 받는다) — 먼저 앞으로.
            guard activeProject != nil else { return false }
            raiseMainIfNeeded(from: windowId)
            requestAddScript()
            return true
        case .runOneOff:
            // 등록 프로젝트가 없어도 부를 수 있다 — 실행 시점에 활성 프로젝트를 대상으로 삼는다.
            // 도크는 메인 전용이라 먼저 메인을 앞으로(⌘J·스크립트 추가와 같은 규칙).
            raiseMainIfNeeded(from: windowId)
            requestRunOneOff()
            return true
        case .closeTab where windowId.isMain && showServiceDock:
            // ⌘W 오폭 방지 — 도크가 열려 있으면 ⌘W는 도크를 닫는다.
            // **메인 창에서만.** 도크는 메인에만 있으므로, 분리 창의 ⌘W까지 여기서 가로채면
            // 그 창의 탭 대신 보이지도 않는 메인의 도크가 닫힌다.
            //
            // 도크의 attach 터미널이 firstResponder여도 Bonsplit의 focusedPaneId는 여전히 뒤의 칸을
            // 가리킨다. 그대로 두면 사용자는 "지금 보고 있는 것(도크)"을 닫으려 ⌘W를 눌렀는데
            // **보이지도 않는 탭이 닫힌다.** 눈에 보이는 것이 닫히는 게 유일하게 옳은 동작이다.
            closeServiceDock()
            return true
        case .newTerminal, .split, .closeTab, .find, .focusPane, .cycleTab:
            guard let store = store(ownedBy: windowId) else { return false }
            return Self.perform(action, store: store)
        }
    }

    /// 크로스윈도우 동작은 사이드바·팔레트가 있는 메인 창에서만 의미가 있다 — 분리 창에서 눌렀으면 먼저 앞으로.
    private func raiseMainIfNeeded(from windowId: WindowID) {
        guard !windowId.isMain else { return }
        windowHost?.raise(.main)
    }

    /// 활성 스토어(분할·탭 컨트롤러) 대상 동작 실행 — 스토어 상태만 만지는 라우팅.
    private static func perform(_ action: KeymapAction, store: TerminalStore) -> Bool {
        let controller = store.controller
        switch action {
        case .newTerminal:
            _ = store.newTerminal(inPane: controller.focusedPaneId)
        case .split(let vertical):
            _ = controller.splitPane(orientation: vertical ? .vertical : .horizontal)
        case .closeTab:
            store.closeActiveTab() // 그룹 탭이면 서브탭 우선 닫기(store가 판단)
        case .find:
            store.focusedTerm?.startSearch()
        case .focusPane(let direction):
            controller.navigateFocus(direction: direction)
        case .cycleTab(let forward):
            forward ? controller.selectNextTab() : controller.selectPreviousTab()
        default:
            return false // 스토어 비대상 동작은 상위 perform이 이미 처리 — 방어적 폴백.
        }
        return true
    }

    // MARK: 다음 대기 세션 전역 점프 (⌘⇧A — 알림→소비 동선의 마지막 조각)

    /// 배지(대기) 있는 칸 하나의 전역 위치 + 순회 순위. 워크스페이스→프로젝트→탭 순으로 안정 정렬한다.
    private struct WaitingSlot {
        let workspaceId: String
        let projectId: String
        let tabId: TabID
        let rank: [Int] // [워크스페이스 idx, 프로젝트 idx, 탭 idx] — 사전식 비교로 순회 순서 결정.
    }

    /// 배지 있는 모든 칸을 안정 순서로 나열한다(워크스페이스→프로젝트→탭 순).
    /// 배지는 실행 중 스토어에서만 생기므로(미생성 프로젝트는 배지 없음) stores로 순회해도 누락이 없다.
    private func waitingSlots() -> [WaitingSlot] {
        var slots: [WaitingSlot] = []
        for (wsIdx, ws) in workspaces.enumerated() {
            for (pIdx, project) in ws.projects.enumerated() {
                guard let store = stores[project.id], store.hasBadge else { continue }
                for (tIdx, tabId) in store.controller.allTabIds.enumerated()
                where store.badgedTabs.contains(tabId) {
                    slots.append(WaitingSlot(workspaceId: ws.id, projectId: project.id, tabId: tabId,
                                             rank: [wsIdx, pIdx, tIdx]))
                }
            }
        }
        return slots
    }

    /// 현재 위치의 전역 순위(사전식) — activeWorkspace→activeProject→활성 스토어의 선택 탭.
    /// 이 순위보다 뒤에 있는 첫 대기 슬롯이 "다음 대기 세션"이 된다.
    private func cursorRank() -> [Int] {
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == activeId }) else { return [-1, -1, -1] }
        let ws = workspaces[wsIdx]
        let pIdx = ws.projects.firstIndex(where: { $0.id == ws.activeProjectId }) ?? -1
        var tIdx = -1
        if let project = ws.activeProject, let store = stores[project.id],
           let pane = store.controller.focusedPaneId,
           let tab = store.controller.selectedTab(inPane: pane) {
            tIdx = store.controller.allTabIds.firstIndex(of: tab.id) ?? -1
        }
        return [wsIdx, pIdx, tIdx]
    }

    /// ⌘⇧A — 다음 대기(배지) 세션으로 워크스페이스 경계를 넘어 순환 점프한다.
    /// 현재 위치 다음 배지 칸으로, 없으면 처음으로 돌아가 순환한다. 배지가 하나도 없으면 무동작.
    func jumpToNextWaiting() {
        let slots = waitingSlots()
        guard !slots.isEmpty else {
            // 탭 배지는 이미 풀렸는데 **프로젝트 배지만 남은** 경우가 있다(스토어가 없는 프로젝트 등).
            // 사이드바 큐 헤더는 badgedProjects를 보고 떠 있으므로, 여기서 무동작하면
            // "떠 있는데 눌러도 아무 일이 없는 줄"이 된다 — 프로젝트 단위 진실로 폴백한다.
            if let ref = nextWaiting { revealActivity(projectId: ref.projectId) }
            return
        }
        let cursor = cursorRank()
        // 현재 위치보다 뒤(사전식)인 첫 슬롯, 없으면 첫 슬롯으로 순환.
        let target = slots.first { cursor.lexicographicallyPrecedes($0.rank) } ?? slots[0]
        stores[target.projectId]?.revealTab(target.tabId) // 그 탭 선택·포커스 (+배지 해제) — 창과 무관하게 먼저
        guard !routeToOwner(target.projectId) else { return } // 분리 창이면 그 창만 앞으로
        setActiveId(target.workspaceId)         // 대상 워크스페이스로
        setActiveProject(target.projectId)      // 그 안의 프로젝트로 (+배지 해제)
        NSApp.activate(ignoringOtherApps: true)
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }


    /// 활성 워크스페이스의 활성 프로젝트.
    var activeProject: Project? {
        activeWorkspace?.activeProject
    }

    /// 활성 프로젝트가 도는 폴더 — 서비스 추가의 기본 대상 cwd(서비스 시작 cwd와 같은 규칙).
    var activeProjectCwd: String? {
        guard let p = activeProject else { return nil }
        return p.path ?? activeWorkspace?.path
    }

    // MARK: 사이드바 2단 트리 (판정은 SidebarTree(순수) — 여기선 신호만 모아 넘긴다)

    /// 디스클로저 클릭 — 전환 없이 그 워크스페이스 하나만 접기/펼치기(다른 건 그대로).
    func toggleWorkspaceExpansion(_ id: String) {
        let next = SidebarTree.toggled(expandedWorkspaces, wsId: id)
        guard next != expandedWorkspaces else { return } // 무의미한 저장 방지
        expandedWorkspaces = next
        save()
    }

    /// 뷰 편의(파생 조회) — 규칙을 뷰가 재구현하지 않게.
    func isExpanded(_ wsId: String) -> Bool {
        SidebarTree.isExpanded(wsId: wsId, expanded: expandedWorkspaces)
    }

    // MARK: 프로젝트 행 에이전트 목록 펼침 (기본 펼침 — 접은 것만 영속)

    func isAgentListExpanded(_ projectId: String) -> Bool {
        !collapsedAgentLists.contains(projectId)
    }

    /// 셰브론/활성 행 재클릭 — 이 프로젝트의 에이전트 목록만 접기/펼치기.
    func toggleAgentList(_ projectId: String) {
        if collapsedAgentLists.contains(projectId) { collapsedAgentLists.remove(projectId) }
        else { collapsedAgentLists.insert(projectId) }
        save()
    }

    /// 프로젝트 전환 시 자동 펼침 — 접혀 있을 때만 상태를 바꾼다(무의미한 저장 방지).
    func expandAgentList(_ projectId: String) {
        guard collapsedAgentLists.contains(projectId) else { return }
        collapsedAgentLists.remove(projectId)
        save()
    }

    /// 지금 **작업 중(턴 진행)인 claude 세션이 하나라도 있나** — 사용량 칩이 자기 폴링을 미룰지 판단한다.
    /// 그 세션들이 자기 `/status`용으로 사용량 엔드포인트를 이미 두드리므로, 겹쳐 두드려 429를 부르지 않게.
    /// 이미 만들어진 스토어만 본다(조회가 PTY를 스폰하지 않게 — 다른 집계와 같은 규칙).
    var hasLiveClaudeSession: Bool { stores.values.contains { $0.hasWorkingAgent } }

    /// 프로젝트 행의 상태 — **이미 만들어진 스토어만** 본다.
    /// `store(for:in:)`은 없으면 만든다(= PTY 스폰)이라, 트리를 그리는 것만으로 안 보고 있는 프로젝트의
    /// 터미널이 전부 떠 버린다. 아직 안 연 프로젝트는 "신호 없음"(유휴)으로 둔다 — 지어내지 않는다.
    func projectStatus(_ projectId: String) -> SidebarTree.ProjectStatus {
        let store = stores[projectId]
        return SidebarTree.status(SidebarTree.ProjectSignal(
            isBadged: badgedProjects.contains(projectId),
            isWaiting: store?.hasWaitingAgent ?? false,
            isWorking: store?.hasWorkingAgent ?? false,
            hasDeadService: hasDeadService(projectId)
        ))
    }

    /// 워크스페이스 롤업 — 자식 중 가장 센 신호(접힌 그룹·icon·slim 막대가 쓴다).
    func workspaceStatus(_ workspace: Workspace) -> SidebarTree.ProjectStatus {
        SidebarTree.rollup(workspace.projects.map { projectStatus($0.id) })
    }

    /// 프로젝트 행 **리딩 아이콘**의 톤 = 경보 헤드라인. `projectStatus`(3값)보다 잘게 —
    /// **죽은 서비스는 실패(빨강 ⚠)**로, 대기/배지는 주의(호박 …), 작업중은 active(틸 ●), 그 외 유휴.
    /// 죽음을 대기와 구분해 "무엇이 났나"가 리딩에서 바로 읽힌다. 서비스 **정상 실행중**(파랑)은 리딩을 올리지
    /// 않는다 — 그건 오른쪽 서비스 요약이 따로 말한다. 우선순위: 실패 > 주의 > 작업중 > 유휴.
    func projectLeadingTone(_ projectId: String) -> StatusTone {
        if hasDeadService(projectId) { return .failure }
        let store = stores[projectId]
        if badgedProjects.contains(projectId) || store?.hasWaitingAgent == true { return .attention }
        if store?.hasWorkingAgent == true { return .active }
        return .quiet
    }

    /// 사이드바 분포 아이콘 클릭 — 그 프로젝트의 **해당 상태 다음 탭으로 순환 점프**한다(여럿이면 누를 때마다
    /// 다음). 매칭 탭이 없으면 무동작. 분리 창에 있으면 그 창을 앞으로만(revealActivity와 같은 분기).
    func jumpToProjectTab(_ projectId: String, matching states: Set<AgentActivity>) {
        guard let ws = workspace(containing: projectId), let store = stores[projectId] else { return }
        guard store.revealNextTab(matching: states) else { return } // 탭 선택은 소유 창과 무관하게 먼저
        guard !routeToOwner(projectId) else { return }               // 분리 창이면 그 창만 앞으로
        setActiveId(ws.id)
        setActiveProject(projectId)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 에이전트 목록 행 클릭 — 그 **특정 탭**을 앞으로 가져온다(`jumpToProjectTab`은 상태별 순환, 이건 지목).
    /// 분리 창에 있으면 그 창만 앞으로(메인의 활성 좌표는 안 건드림). 탭 UUID 문자열을 TabID로 되살린다.
    func focusAgentTab(_ projectId: String, _ tabId: TabID) {
        guard let ws = workspace(containing: projectId), let store = stores[projectId] else { return }
        store.revealTab(tabId)                          // 탭 선택은 소유 창과 무관하게 먼저
        guard !routeToOwner(projectId) else { return }  // 분리 창이면 그 창만 앞으로
        setActiveId(ws.id)
        setActiveProject(projectId)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 프로젝트 탭을 **상태별로 집계**한다(작업중·대기·완료·유휴 각 몇 탭) — 사이드바가 분포를 아이콘+개수로.
    /// **이미 만들어진 스토어만** 본다(트리를 그리는 것만으로 PTY 스폰 금지). 안 연 프로젝트는 전부 0.
    /// 판정은 탭별 `agentActivity(for:)` 한 출처 — **done은 유휴에 접지 않고 따로 센다**(패인 테두리 초록과
    /// 일치하게, C2). done 탭은 사용자가 보면 acknowledge로 idle이 되어 자연히 사라진다.
    /// **터미널 탭만** 센다 — 뷰어(그룹)·링크 탭은 상태가 없어 항상 idle로 판정되므로, 세면 유휴 개수가
    /// 부풀고 순환 점프(`revealNextTab`)와 어긋난다(같은 모집단 유지).
    func projectTabStatus(_ projectId: String) -> (working: Int, waiting: Int, done: Int, idle: Int) {
        guard let store = stores[projectId] else { return (0, 0, 0, 0) }
        var working = 0, waiting = 0, done = 0, idle = 0
        for tabId in store.controller.allTabIds {
            guard case .terminal = store.content(for: tabId) else { continue }
            switch store.agentActivity(for: tabId) {
            case .working: working += 1
            case .waiting: waiting += 1
            case .done: done += 1   // idle에 접지 않는다 — 완료는 별도 표기(패인 테두리 초록과 일치, C2)
            case .idle: idle += 1
            }
        }
        return (working, waiting, done, idle)
    }

    /// 프로젝트의 열린 탭 개수(터미널+뷰어) — 사이드바 프로젝트 행의 개수 배지가 쓴다.
    /// 연 프로젝트는 라이브 탭을, **아직 안 연(lazy) 프로젝트는 복원 스냅샷**을 센다
    /// (스토어를 만들지 않는다 — 조회가 PTY를 스폰하면 안 된다). 둘 다 없으면 0(배지 숨김).
    func projectTabCount(_ projectId: String) -> Int {
        if let store = stores[projectId] { return store.controller.allTabIds.count }
        return savedLayouts[projectId]?.tabCount() ?? 0
    }

    /// 프로젝트 행을 펼쳤을 때의 **에이전트 목록** — 이미 만들어진 스토어의 탭을 긴급도순으로 정렬해 돌려준다.
    /// 안 연 프로젝트는 빈 배열(조회가 PTY를 스폰하지 않는다). 정렬은 순수 함수 `AgentRow.ordered`.
    func agentRows(_ projectId: String) -> [AgentRow] {
        guard let store = stores[projectId] else { return [] }
        return AgentRow.ordered(store.agentRows())
    }

    /// 프로젝트의 "지금 보고 있는" 탭(포커스 칸의 선택 탭) — 사이드바 에이전트 목록의 활성 행 표시용.
    func selectedTabId(_ projectId: String) -> TabID? {
        stores[projectId]?.currentTabId
    }

    /// 탭의 transcript(JSONL) 경로 — 사이드바 hover 카드가 첨부 이미지를 읽을 때 쓴다.
    func agentTranscript(_ projectId: String, _ tabId: TabID) -> String? {
        stores[projectId]?.agentTranscript(for: tabId)
    }

    /// 열려 있는 터미널이 하나라도 있나 — 사이드바 ✕(닫기) 노출 판정.
    /// 터미널이 살아 있으면 ✕를 숨긴다(실수 클릭 한 번이 모든 세션을 죽인다 — 닫기는 우클릭 메뉴로).
    /// 안 연 프로젝트(store 없음)는 false — 세션이 없으니 ✕가 떠도 안전하다.
    func hasOpenTerminals(_ projectId: String) -> Bool {
        stores[projectId]?.hasTerminalTabs ?? false
    }

    // MARK: 워크스페이스 리포 아바타 — git remote → GitHub owner 아바타 (orca식 리포 아이콘)

    /// 워크스페이스 id → 아바타 URL. **"없음"(nil)도 캐시**한다(이중 옵셔널 — 키 존재 = 판정 완료).
    /// remote 없음·비 GitHub 워크스페이스에서 행이 그려질 때마다 셸아웃이 재실행되지 않게.
    private(set) var repoAvatars: [String: URL?] = [:]

    /// 이 워크스페이스의 아바타 URL(판정 전·없음이면 nil → 뷰는 레이어 글리프/이니셜 폴백).
    func repoAvatar(_ workspaceId: String) -> URL? {
        repoAvatars[workspaceId] ?? nil
    }

    /// 아바타 판정 1회 — 행이 나타날 때 불린다(`.task`). 이미 판정한 워크스페이스는 no-op.
    /// remote는 사실상 안 바뀌므로 세션 내 재조회하지 않는다.
    func loadRepoAvatar(for workspace: Workspace) async {
        guard repoAvatars[workspace.id] == nil else { return }
        guard let path = workspace.path else { // 경로 없는 워크스페이스 — 아바타 없음으로 확정
            repoAvatars[workspace.id] = .some(nil)
            return
        }
        let url = await GitService.remoteURL(in: path)
            .flatMap(RepoRemote.githubSlug(from:))
            .flatMap(RepoRemote.avatarURL)
        repoAvatars[workspace.id] = .some(url)
    }

    /// 프로젝트 서비스들의 현재 상태.
    func serviceStatuses(of projectId: String) -> [ServiceState] {
        services(of: projectId).map { serviceMonitor.state(of: $0.id) }
    }

    private func hasDeadService(_ projectId: String) -> Bool {
        ServiceStatusStyle.summarize(serviceStatuses(of: projectId)).isFailure
    }

    /// ⌘⇧A 폴백이 가리킬 첫 대기 프로젝트(`jumpToNextWaiting`).
    var nextWaiting: SidebarTree.WaitingRef? {
        SidebarTree.firstWaiting(workspaces: workspaces, badged: badgedProjects)
    }

    /// 주의 큐 카드 한 행의 표시 스냅샷 — 순수 참조(`WaitingRef`) 위에 경계만 아는 표시 정보를 얹는다.
    struct WaitingQueueEntry: Equatable, Identifiable {
        let ref: SidebarTree.WaitingRef
        /// 워크트리처럼 경로가 신원인 프로젝트 — 이름을 모노로(`Project.usesMonoName`).
        let usesMonoName: Bool
        /// 대기 경과(초) — 그 프로젝트 대기 탭 중 가장 오래된 것. 못 재면 nil(**지어내지 않는다** —
        /// 배지만 남고 스토어가 없는 프로젝트 등).
        let waitingSeconds: TimeInterval?
        var id: String { ref.projectId }
    }

    /// 주의 큐 카드의 행 목록 — 비면 카드를 아예 그리지 않는다. 순서는 ⌘⇧A 순회(`waitingSlots`)와 같다.
    var waitingQueue: [WaitingQueueEntry] {
        SidebarTree.allWaiting(workspaces: workspaces, badged: badgedProjects).map { ref in
            let project = workspace(containing: ref.projectId)?.projects.first { $0.id == ref.projectId }
            let seconds = stores[ref.projectId]?.agentRows().compactMap(\.waitingSeconds).max()
            return WaitingQueueEntry(ref: ref, usesMonoName: project?.usesMonoName ?? false,
                                     waitingSeconds: seconds)
        }
    }

    /// 큐 카드 행 클릭 — 그 프로젝트의 **대기 탭**으로 지목 이동. 대기 탭이 안 잡히면(배지만 남은
    /// 프로젝트 등) 프로젝트 이동으로만 폴백한다 — 떠 있는 행이 눌러도 무동작이면 거짓말이 된다.
    func jumpToWaiting(projectId: String) {
        if let store = stores[projectId] {
            _ = store.revealNextTab(matching: [.waiting]) // 탭 선택은 소유 창과 무관하게 먼저(§5.3)
        }
        revealActivity(projectId: projectId, openGitPanel: false) // 배지 해제·창 라우팅·활성화까지
    }

    /// **메인 창이 실제로 그리고 있는** 프로젝트의 스토어(단축키 대상 — ⌘T/⌘D/⌘W/⌘F).
    ///
    /// 활성 프로젝트가 분리 창에 있으면 nil이다 — 메인은 그때 SeparatedPlaceholder를 그리고 있고,
    /// 소유권이 곧 키 라우팅의 자격이다(I3). 이 가드가 없으면 메인의 ⌘W가 **보이지도 않는 다른 창의**
    /// 살아 있는 탭을 닫고 그 PTY까지 죽인다.
    var mainStore: TerminalStore? {
        guard let ws = activeWorkspace, let project = ws.activeProject,
              owner(of: project.id).isMain else { return nil }
        return store(for: project, in: ws)
    }

    /// **이미 만들어진** 스토어만 — 없으면 nil. 생성은 PTY 스폰이라 조회 경로가 만들면 안 된다.
    /// (확장 파일에서 `stores`(private)에 닿을 수 없어 여는 창구.)
    func existingStore(_ projectId: String) -> TerminalStore? { stores[projectId] }

    /// 프로젝트의 터미널 스토어(없으면 생성). cwd는 프로젝트 경로(없으면 워크스페이스 경로 상속).
    func store(for project: Project, in workspace: Workspace) -> TerminalStore {
        if let s = stores[project.id] { return s }
        let cwd = project.path ?? workspace.path
        let s = TerminalStore(app: app, cwd: cwd, restoreSnap: savedLayouts[project.id],
                              commandFinishedThresholdNs: config.commandFinishedThresholdNs,
                              agentResumeMode: config.agentResume,
                              sessionWasDirty: lastLaunchWasDirty,
                              projectId: project.id)
        let pid = project.id
        s.onProjectActivity = { [weak self] in MainActor.assumeIsolated { self?.markProjectBadge(pid) } }
        // 탭을 닫았는데 안에서 작업이 돌고 있었다 → 백그라운드로 남기고 기록한다(GC 보존 + 복구 목록).
        s.onDetachSession = { [weak self] detached in
            MainActor.assumeIsolated { self?.recordDetached(detached, in: pid) }
        }
        // 데스크톱 알림에 라우팅 컨텍스트(프로젝트·워크스페이스)를 붙여 발사 — 클릭 시 원클릭 검토로 이어짐.
        s.onNotify = { [weak self] tabId, title, body in
            MainActor.assumeIsolated { self?.emitNotification(projectId: pid, tabId: tabId, title: title, body: body) }
        }
        // 배지가 붙는 순간 인박스 이력에 한 건 기록 — 라우팅 컨텍스트(워크스페이스)는 여기서 파생.
        s.onAttention = { [weak self] tabId, kind, title in
            MainActor.assumeIsolated { self?.recordAttention(projectId: pid, tabId: tabId, kind: kind, title: title) }
        }
        // 탭/뷰어가 바뀔 때마다 즉시 저장 — ⌘Q 없이(pkill·크래시) 종료돼도 다음 실행에 복원.
        s.onStateChange = { [weak self] in MainActor.assumeIsolated { self?.save() } }
        // 셸이 새 워크트리로 들어갔을 수 있다(에이전트의 worktree add + cd) — 자동 승격을 판정한다(D31 보완).
        s.onPwdChange = { [weak self] in self?.autoImportWorktrees() }
        // 워크트리 링크 탭(D31) — 대상 판정·프로젝트를 넘나드는 액션은 AppState 몫(스토어는 다른 프로젝트를 모른다).
        s.worktreeLink = { [weak self] in self?.externalLiveSession(for: pid) }
        s.onWorktreeLinkAction = { [weak self] link, action in
            switch action {
            case .go: self?.focusAgentTab(link.originProjectId, link.tabId)
            case .bring: self?.bringPersistentTab(from: link.originProjectId, tabId: link.tabId, to: pid)
            }
        }
        // 자동 승격된 워크트리(밖에 라이브 세션이 있는) 프로젝트의 첫 화면은 터미널 대신 **링크 탭** —
        // 복원 스냅샷이 있으면 그쪽이 우선이라 힌트는 무시된다(ensureInitialTerminal).
        s.initialWorktreeLink = savedLayouts[project.id] == nil && externalLiveSession(for: pid) != nil
        // 이동 배너(D31 이동 배지) — 이 프로젝트의 ∞ 탭이 다른 프로젝트의 워크트리 안에서 작업 중이면 "옮길까요?".
        s.moveSuggestion = { [weak self] tabId in self?.worktreeMoveSuggestion(for: tabId, in: pid) }
        s.onWorktreeMove = { [weak self] tabId, targetId in
            self?.bringPersistentTab(from: pid, tabId: tabId, to: targetId)
        }
        // 늦게 열리는 프로젝트도 자기 창 소유권을 갖고 태어난다 — 분리 창의 프로젝트가 "메인 소유"로
        // 만들어지면 그 안의 TermView는 어느 창에도 붙지 않는다(I3).
        s.setOwnerWindow(owner(of: project.id), focusedTab: nil)
        stores[project.id] = s
        // 첫 store 생성(=첫 터미널이 이 경로에서 시작) 시점에 세션 기준선을 1회 기록(ARCHITECTURE 4.4 #2).
        recordSessionBaseline(projectId: project.id, cwd: cwd)
        return s
    }

    // MARK: 세션 기준선 (ARCHITECTURE 4.4 #2 — "이번 세션에 에이전트가 한 일"의 기준점)

    /// 프로젝트의 세션 기준선을 최초 1회 기록한다 — 이미 값이 있으면 유지(세션 지속). git 저장소가 아니면 무시.
    private func recordSessionBaseline(projectId: String, cwd: String?) {
        guard let cwd, project(projectId)?.sessionBaseHead == nil else { return }
        Task {
            guard let head = await GitService.headHash(in: cwd) else { return }
            // Task 대기 중 다른 경로로 이미 기록됐을 수 있으니 다시 검사 후 설정(중복 방지).
            updateProject(projectId) { p in
                guard p.sessionBaseHead == nil else { return p }
                var next = p
                next.sessionBaseHead = head
                return next
            }
        }
    }

    /// 세션 기준선을 현재 HEAD로 갱신한다("여기까지 봤음" = 읽음 처리). GitPanel 리셋 버튼이 호출.
    func resetSessionBaseline(projectId: String, cwd: String?) {
        guard let cwd else { return }
        Task {
            guard let head = await GitService.headHash(in: cwd) else { return }
            updateProject(projectId) { p in
                var next = p
                next.sessionBaseHead = head
                return next
            }
        }
    }

    /// 이 프로젝트를 품은 워크스페이스(어느 것이든). 소속 파생의 단일 진실 원천 — 워크스페이스 id·이름을
    /// 프로젝트에서 되짚는 여러 경로(알림·인박스·라벨·점프)가 이 한 곳을 공유한다.
    private func workspace(containing projectId: String) -> Workspace? {
        workspaces.first { $0.projects.contains { $0.id == projectId } }
    }

    /// 프로젝트 id로 프로젝트를 찾는다(어느 워크스페이스든).
    private func project(_ projectId: String) -> Project? {
        workspace(containing: projectId)?.projects.first { $0.id == projectId }
    }

    // MARK: 서비스 (장수 프로세스 — Service.swift, 실행은 tmux 위임)

    /// tmux를 쓸 수 있나 — **뷰는 이것만 본다**(`TmuxService.isAvailable`을 직접 읽지 않는다).
    ///
    /// static은 @Observable이 아니다. 뷰가 그걸 직접 읽으면 사용자가 tmux를 설치하고 재탐지에
    /// 성공해도 SwiftUI가 무효화를 못 봐 **푸터 칩도 도크도 그대로 "tmux 없음"으로 남는다** —
    /// 설치했는데 아무 일도 안 일어나는 화면이 된다. 관측 가능한 사본을 여기 한 벌 둔다.
    private(set) var servicesAvailable = TmuxService.isAvailable

    /// tmux를 다시 찾는다(사용자가 방금 설치했다). 찾았으면 UI를 살리고 저장된 서비스를 띄운다.
    ///
    /// 재탐지(셸아웃)와 기동(전역 동작)은 **뷰가 할 일이 아니다** — 뷰는 결과만 받는다.
    /// - Returns: 찾았으면 true.
    @discardableResult
    func retryTmuxDetection() -> Bool {
        guard TmuxService.refresh() else { return false }
        servicesAvailable = true
        startServices() // 찾았으니 저장된 서비스를 바로 띄운다
        return true
    }

    /// 프로젝트에 등록된 서비스 목록.
    func services(of projectId: String) -> [Service] {
        project(projectId)?.services ?? []
    }

    /// 모든 워크스페이스의 서비스 — 모니터 폴링의 입력. 트리 순회는 `collectAllServices`(순수) 하나뿐이다
    /// (같은 순회를 손으로 다시 쓰면 "활성 워크스페이스만 훑는" 실수가 한쪽에서만 되살아난다).
    private var allServices: [Service] {
        allLocatedServices.map(\.service)
    }

    /// 서비스를 등록하고 곧바로 기동한다. cwd는 프로젝트 경로(없으면 워크스페이스 경로).
    // MARK: 백그라운드로 남긴 터미널 세션 (L3 — 닫았지만 안에서 작업이 돌던 탭)

    /// 남긴 세션을 프로젝트에 기록한다 — GC가 죽이지 않고, 사용자가 목록에서 되찾을 수 있게.
    /// 인박스에도 한 줄 남긴다(**말없이 남기면 유령이다** — 사용자가 존재를 알아야 한다).
    func recordDetached(_ detached: DetachedSession, in projectId: String) {
        updateProject(projectId) { p in
            var next = p
            var list = (p.detached ?? []).filter { $0.session != detached.session }
            list.append(detached)
            next.detached = list
            return next
        }
        attention.recordSystem(title: "터미널을 닫았지만 \(detached.command)가 돌고 있어 백그라운드에 남겼습니다.")
    }

    /// 남긴 세션 목록에서 지운다(되찾았거나 사용자가 종료했을 때).
    func dropDetached(_ session: String, from projectId: String) {
        updateProject(projectId) { p in
            var next = p
            next.detached = (p.detached ?? []).filter { $0.session != session }
            return next
        }
    }

    /// 남긴 세션을 **완전히 종료**한다(사용자가 목록에서 버릴 때).
    func killDetached(_ session: String, from projectId: String) {
        dropDetached(session, from: projectId)
        Task { await TmuxService.kill(session: session) }
    }

    /// 남긴 세션을 새 탭으로 되찾는다 — 안에서 돌던 프로세스와 화면이 그대로 돌아온다.
    func reattachDetached(_ detached: DetachedSession, in projectId: String) {
        guard let store = stores[projectId] else { return }
        store.reattach(detached)
        dropDetached(detached.session, from: projectId)
    }

    /// 서비스를 등록하고 곧바로 띄운다. `cwd`는 **서비스 자체 실행 폴더 지정**(nil = 프로젝트 경로 상속) —
    /// 시작 경로는 등록 후 `locateService`가 해석한다(시작·재시작·attach가 같은 규칙 하나를 쓰게).
    func addService(name: String, command: String, to projectId: String, cwd: String? = nil) {
        let service = Service(id: newId(), name: name, command: command, cwd: cwd)
        updateProject(projectId) { p in
            var next = p
            next.services = (p.services ?? []) + [service]
            return next
        }
        Task {
            let startCwd = locateService(service.id, in: workspaces)?.cwd ?? ""
            reportServiceStart(await TmuxService.start(service, projectId: projectId, cwd: startCwd), service)
            syncServiceMonitor()
        }
    }

    /// 서비스 기동 실패를 인박스에 표면화한다(성공이면 무동작). 실패해도 상태는 회색 점선(.missing)이라
    /// "아직 안 띄운 것"과 똑같이 보인다 — 사유를 여기서만 말할 수 있다. dedup은 AttentionLog가 한다.
    private func reportServiceStart(_ reason: String?, _ service: Service) {
        guard let reason else { return }
        attention.recordSystem(title: "\(service.name) 시작 실패 — \(reason)")
    }

    /// 서비스를 등록 해제하고 프로세스도 죽인다.
    ///
    /// **등록만 지우면 좀비가 된다** — tmux 세션은 muxa와 무관하게 살아남아 포트를 계속 문다.
    /// 그래서 여기서 반드시 함께 죽인다. 그럼에도 놓친 것(앱이 죽은 사이 등록이 사라진 경우 등)은
    /// 시작 시 collectServiceGarbage가 쓸어간다 — 두 겹 방어.
    func removeService(_ serviceId: String, from projectId: String) {
        let removed = services(of: projectId).first { $0.id == serviceId }
        let log = finalLogs[serviceId]
        updateProject(projectId) { p in
            var next = p
            next.services = (p.services ?? []).filter { $0.id != serviceId }
            return next
        }
        if selectedServiceId == serviceId { selectedServiceId = nil }
        userStoppedServiceIds.remove(serviceId) // 등록이 사라지면 오버레이도 정리(누수 방지)
        finalLogs[serviceId] = nil
        dropDockTerm(serviceId)
        Task {
            await TmuxService.kill(projectId: projectId, serviceId: serviceId)
            syncServiceMonitor()
        }
        if let removed { queueUndoDeletion(label: removed.name, projectId: projectId, service: removed, script: nil, finalLog: log) }
    }

    /// 죽은 서비스를 같은 명령으로 다시 띄운다(재시작). tmux 세션을 지우고 새로 만든다.
    ///
    /// **자동 재시작은 하지 않는다.** 포트를 문 좀비나 설정 오류로 즉사하는 경우 크래시 루프에 빠져
    /// 로그가 덮여 원인이 사라진다. 죽으면 그대로 두고(remain-on-exit로 로그가 보존된다) 사용자가
    /// 로그를 본 뒤 직접 누르게 한다.
    func restartService(_ serviceId: String, in projectId: String, cwd: String) {
        guard let service = services(of: projectId).first(where: { $0.id == serviceId }) else { return }
        userStoppedServiceIds.remove(serviceId) // 다시 띄우면 "중단됨" 표시를 내린다
        dropDockTerm(serviceId) // 옛 세션에 attach된 터미널은 버린다 — 다시 열 때 새 세션에 붙는다
        Task {
            await TmuxService.kill(projectId: projectId, serviceId: serviceId)
            reportServiceStart(await TmuxService.start(service, projectId: projectId, cwd: cwd), service)
            syncServiceMonitor()
        }
    }

    /// **사용자가 껐다** — 프로세스(세션)만 종료하고 **등록은 남긴다**(삭제와 다르다). 다시 등록·실행하는
    /// 수고 없이 껐다 켤 수 있다. 세션이 사라져 다음 폴은 `.missing`을 보고하는데, 그걸 "실행 전"이 아니라
    /// **중단됨**으로 갈라 보이게 id를 오버레이에 담는다(`ServiceDisplay`). 순진하게 프로세스만 죽이면
    /// tmux가 exit 143으로 읽어 `isFailure` → 거짓 실패 알림·빨간 배지가 뜨는데, 세션 kill이 그 원천을 없앤다.
    func stopService(_ serviceId: String, in projectId: String) {
        userStoppedServiceIds.insert(serviceId) // 표시를 먼저 세운다(kill↔폴 사이 "실행 전" 깜빡임 방지)
        dropDockTerm(serviceId)
        Task {
            // 세션을 지우기 전에 마지막 화면을 스냅샷 — kill하면 pane 로그가 사라진다(③ 로그 보존).
            if let session = ServiceSession.name(projectId: projectId, serviceId: serviceId) {
                let raw = await TmuxService.capture(session: session, lines: 400)
                if !ServiceLogView.tidy(raw).isEmpty { finalLogs[serviceId] = raw }
            }
            await TmuxService.kill(projectId: projectId, serviceId: serviceId)
            syncServiceMonitor()
        }
    }

    /// 사용자가 중단한 서비스 id — 세션 kill로 `.missing`이 된 것을 "중단됨"으로 갈라 표시하는 오버레이.
    /// 비영속(세션 한정) — muxa 재시작 시 `startServices`가 자동 기동하므로 중단은 유지되지 않는다.
    private(set) var userStoppedServiceIds: Set<String> = []

    /// 서비스·스크립트·일회용의 **종료 시점 로그 스냅샷**(id 키) — 세션 pane이 사라져도(재실행·중단·tmux
    /// 사망) 마지막 로그를 살린다. `ServiceLogView`가 라이브 캡처가 비면 이걸 폴백으로 쓴다.
    /// 값 타입(`ScriptRun`) 본문에 넣지 않는다 — merge의 `==` 비교가 수백 줄 문자열을 물면 리렌더가 무거워진다.
    private(set) var finalLogs: [String: String] = [:]

    // MARK: 등록 해제 실행취소 — 되돌릴 수 없는 파괴를 잠깐(6초) 되돌릴 수 있게 (2단계 확인의 상위 안전망)

    /// 방금 등록 해제된 것 — 스낵바가 떠 있는 동안 되돌리면 등록·로그를 복원한다. 프로세스는 이미
    /// 종료됐으므로 '실행 전'으로 돌아온다(재실행 한 번이면 다시 뜬다) — 되찾는 건 다시 타이핑하기 번거로운
    /// **등록(이름·명령)과 로그**다. 일회용 기록 삭제는 저위험이라 undo 대상이 아니다.
    struct PendingDeletion: Identifiable, Equatable {
        let id: String
        let label: String
        let projectId: String
        let service: Service?
        let script: Script?
        let finalLog: String?
        var itemId: String { service?.id ?? script?.id ?? "" }
    }
    private(set) var pendingDeletion: PendingDeletion?
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    /// 등록 해제 직후 스낵바를 띄우고 6초 뒤 스스로 내린다(그 안에 안 되돌리면 확정).
    private func queueUndoDeletion(label: String, projectId: String, service: Service?, script: Script?, finalLog: String?) {
        pendingDeletion = PendingDeletion(id: newId(), label: label, projectId: projectId,
                                          service: service, script: script, finalLog: finalLog)
        undoTask?.cancel()
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.pendingDeletion = nil
        }
    }

    /// 되돌리기 — 등록을 프로젝트에 다시 넣고 로그 스냅샷을 복원한 뒤 그 항목을 선택한다.
    func undoDeletion() {
        guard let pd = pendingDeletion else { return }
        undoTask?.cancel()
        if let s = pd.service {
            updateProject(pd.projectId) { p in var n = p; n.services = (p.services ?? []) + [s]; return n }
        }
        if let s = pd.script {
            updateProject(pd.projectId) { p in var n = p; n.scripts = (p.scripts ?? []) + [s]; return n }
        }
        if let log = pd.finalLog { finalLogs[pd.itemId] = log }
        selectedServiceId = pd.itemId
        syncServiceMonitor()
        pendingDeletion = nil
    }

    func dismissUndo() { undoTask?.cancel(); pendingDeletion = nil }

    /// 로그 뷰가 라이브로 읽어낸 비지 않은 로그를 스냅샷으로 굳힌다 — 한 번 본 로그는 pane이 정리돼도 남는다.
    func recordFinalLog(_ id: String, _ raw: String) {
        if !ServiceLogView.tidy(raw).isEmpty { finalLogs[id] = raw }
    }

    // MARK: 스크립트 (끝이 있는 명령 — Script.swift)
    //
    // 서비스 CRUD의 미러. 실행도 서비스와 **같은 tmux 백엔드**지만(탭 없음 — 백그라운드),
    // 자동 기동은 없다 — 사용자가 그때그때 명시적으로 시킨다. 결과는 scriptRuns 레지스트리가 들고,
    // 관측은 serviceMonitor의 같은 폴링(onScriptsPoll)이, 전이는 순수 함수(ScriptRun.merging)가 한다.

    /// 실행 레지스트리 — scriptId 키, **창 전체**(도크가 전역이므로). 푸터 칩은 프로젝트로 거른다.
    private(set) var scriptRuns: [String: ScriptRun] = [:]

    /// 기동 중(킬→새 세션 생성이 아직 안 끝난) 스크립트 — 이 동안의 tmux 관측은 **버린다**.
    /// 안 버리면 in-flight 폴 스냅샷이 **이전 실행의 종료 pane**을 보고 새 실행을 그 exit code로
    /// 오판한다(가짜 ✗ + 가짜 실패 알림, 다음 폴에서야 running으로 복구되는 깜빡임).
    /// 보류 중 관측은 "없음"으로 취급되고, 갓 심은 running은 merge의 유예(missingGrace)가 지켜준다.
    @ObservationIgnored private var pendingScriptStarts: Set<String> = []

    // MARK: 일회용 명령 (즉석 1회 실행 — 등록 안 함, 세션 한정 히스토리)
    //
    // 스크립트와 **같은 실행 기구**(tmux·ScriptRun·ScriptSession·ScriptStatusStyle)를 재사용하되,
    // `Project.scripts`에 저장하지 않는다 — 즉석 명령(brew install·pnpm install)이라 "등록해 반복"이
    // 아니라 "쳐서 한 번"이다. 히스토리는 세션 한정(비영속)·상한(LRU)이고, 다음 실행 세션에서 GC가
    // 자동 청소한다(collectLiveScriptIds에 안 넣으므로). 실행 중엔 merge 추적집합이 지켜준다.

    /// 일회용 실행 히스토리(최신이 뒤). 세션 한정·비영속. 상한 초과 시 **완료분 중 가장 오래된 것**부터 축출.
    private(set) var oneOffScripts: [Script] = []
    /// 히스토리 상한 — 넘으면 완료된 오래된 항목부터 세션·로그·run을 정리한다(실행 중은 보존).
    static let oneOffHistoryLimit = 20

    /// 일회용을 스크립트와 같은 폴링·병합·상세 경로에 태우기 위한 위치정보. **활성 프로젝트 소속**으로
    /// 만든다(⌘K·입력창이 raiseMain 후 실행하므로 항상 메인의 활성 프로젝트다). cwd는 프로젝트 경로 상속.
    var oneOffLocatedScripts: [LocatedScript] {
        guard let ws = activeWorkspace, let project = ws.activeProject else { return [] }
        let cwd = activeProjectCwd
        return oneOffScripts.map {
            LocatedScript(script: $0, workspaceId: ws.id, workspaceName: ws.name,
                          projectId: project.id, projectName: project.name, cwd: cwd)
        }
    }

    /// 폴링·병합·GC가 추적할 스크립트 전체 = 등록 스크립트 + 일회용. merge의 `registered`에 일회용이
    /// 빠지면 그 run이 다음 폴(2s)에서 "등록 사라짐"으로 **즉시 증발**한다(Script.merging 규칙).
    var trackedLocatedScripts: [LocatedScript] {
        allLocatedScripts + oneOffLocatedScripts
    }

    /// 이 프로젝트의 **등록 스크립트** 실행들 — 푸터 칩(프로젝트 단위)이 제 것만 본다.
    /// 일회용 run도 활성 프로젝트 소속이라 여기 섞이면 스크립트 칩에 샌다 → 등록 id로 거른다.
    func scriptRuns(of projectId: String) -> [ScriptRun] {
        let registered = Set(scripts(of: projectId).map(\.id))
        return scriptRuns.values.filter { $0.projectId == projectId && registered.contains($0.scriptId) }
    }

    /// **창 전체**의 스크립트 — 소속을 달고 온다(도크 목록·모니터 폴링·GC 입력이 이 하나를 쓴다).
    var allLocatedScripts: [LocatedScript] {
        collectAllScripts(in: workspaces)
    }

    /// 프로젝트에 등록된 스크립트 목록.
    func scripts(of projectId: String) -> [Script] {
        project(projectId)?.scripts ?? []
    }

    /// 스크립트를 등록한다(실행은 별도 — addService와 달리 등록이 곧 기동이 아니다).
    /// `cwd`는 스크립트 자체 실행 폴더 지정(nil = 프로젝트 경로 상속) — 실행 시 `allLocatedScripts`가 해석한다.
    func addScript(name: String, command: String, to projectId: String, cwd: String? = nil) {
        let script = Script(id: newId(), name: name, command: command, cwd: cwd)
        updateProject(projectId) { p in
            var next = p
            next.scripts = (p.scripts ?? []) + [script]
            return next
        }
        syncServiceMonitor() // 폴링 추적 대상 갱신 — 다른 인스턴스의 실행도 이제 관측된다
    }

    /// 스크립트 등록을 해제한다 — **세션도 함께 죽인다**(removeService와 대칭). 등록만 지우면
    /// 실행 중이던 프로세스·종료 로그 pane이 좀비로 남는다(놓친 것은 시작 시 GC가 쓸어간다 — 두 겹 방어).
    func removeScript(_ scriptId: String, from projectId: String) {
        let removed = scripts(of: projectId).first { $0.id == scriptId }
        let log = finalLogs[scriptId]
        updateProject(projectId) { p in
            var next = p
            next.scripts = (p.scripts ?? []).filter { $0.id != scriptId }
            return next
        }
        scriptRuns[scriptId] = nil
        finalLogs[scriptId] = nil
        if selectedServiceId == scriptId { selectedServiceId = nil }
        dropDockTerm(scriptId)
        Task {
            await TmuxService.killScript(projectId: projectId, scriptId: scriptId)
            syncServiceMonitor()
        }
        if let removed { queueUndoDeletion(label: removed.name, projectId: projectId, service: nil, script: removed, finalLog: log) }
    }

    /// 스크립트를 **백그라운드(tmux)** 에서 1회 실행한다 — 탭을 띄우지 않는다. 출력은 서비스 도크에서
    /// 본다(실행 중 = 라이브 터미널, 종료 = 보존된 로그). 같은 스크립트가 이미 도는 중이면 새로 띄우지
    /// 않고 그 출력만 보여준다(dedup — 두 번 눌렀다고 빌드가 두 개 돌면 안 된다).
    func runScript(_ script: Script, in projectId: String) {
        // tmux가 없으면 실행 백엔드가 없다 — 숨기는 대신 도크의 설치 안내(ServiceSetupView)로 보낸다.
        guard TmuxService.isAvailable else {
            openServiceDock(serviceId: nil, projectId: projectId)
            return
        }
        if let run = scriptRuns[script.id], run.isRunning {
            revealScript(scriptId: script.id)
            return
        }
        guard let located = trackedLocatedScripts.first(where: { $0.id == script.id }),
              let cwd = located.cwd else {
            attention.recordSystem(title: "\(script.name) 실행 실패 — 프로젝트 경로가 없습니다")
            return
        }
        launchScript(script, in: projectId, cwd: cwd)
    }

    /// 스크립트·일회용 공통 **실행 코어** — dedup·경로 해석을 마친 뒤의 실제 기동(잔류 확인 + 낙관적
    /// seed + tmux 백그라운드 시작). 두 경로가 이 하나를 공유한다(CLAUDE.md 중복 추출 — 세션 갈아엎기·
    /// pending 차단·재드롭 규칙이 갈라지면 안 된다).
    private func launchScript(_ script: Script, in projectId: String, cwd: String) {
        // 새 실행 시작 = 이 프로젝트의 잔류(✓/✗) 확인 처리 — 칩은 "가장 최근 일"만 말한다.
        scriptRuns = ScriptRun.acknowledgingFinished(scriptRuns, projectId: projectId)
        // 폴링(2s)을 기다리지 않고 낙관적으로 심는다 — 버튼을 눌렀는데 칩이 조용하면 두 번 누른다.
        scriptRuns[script.id] = ScriptRun(scriptId: script.id, projectId: projectId,
                                          name: script.name, startedAt: Date(), state: .running)
        pendingScriptStarts.insert(script.id) // 기동이 끝날 때까지 옛 pane 관측을 차단
        dropDockTerm(script.id) // 옛 세션에 붙은 attach 터미널·로그 뷰 무효화(재시작과 같은 이유)
        syncServiceMonitor() // 새 id(특히 일회용)를 폴링 추적에 즉시 넣는다 — 안 그러면 첫 폴이 관측 못 해 증발
        Task {
            let reason = await TmuxService.startScript(script, projectId: projectId, cwd: cwd)
            pendingScriptStarts.remove(script.id)
            if let reason {
                attention.recordSystem(title: "\(script.name) 실행 실패 — \(reason)")
                scriptRuns[script.id] = nil // 시작 자체가 실패 — running을 남기면 칩이 유령을 돈다
            } else {
                // 기동 완료 후 **한 번 더** 버린다 — 위의 동기 dropDockTerm과 이 시점 사이에 도크가
                // 열려 있었으면(재실행·dedup reveal) SwiftUI가 이미 attach TermView를 만들었는데,
                // 그건 kill→new-session **이전**의 옛/부재 세션에 붙은 죽은 서피스다. 여기서 버리고
                // restartSeq를 올리면 뷰 id가 바뀌어 새 세션 기준으로 갈아 끼워진다(도크 `.id` 참조).
                dropDockTerm(script.id)
            }
            syncServiceMonitor()
        }
    }

    // MARK: 일회용 실행

    /// 일회용 명령을 즉석 1회 실행한다 — 등록 없이 tmux 백그라운드로. 히스토리에 쌓고(상한 LRU),
    /// 도크 일회용 탭에서 출력·종료 로그를 본다. 스크립트와 같은 실행 코어(`launchScript`)를 탄다.
    func runOneOff(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard TmuxService.isAvailable else { openServiceDock(serviceId: nil, tab: .oneoff); return }
        guard let project = activeProject, let cwd = activeProjectCwd else {
            attention.recordSystem(title: "일회용 실행 실패 — 활성 프로젝트가 없습니다")
            return
        }
        // 이름 = 명령 그대로(히스토리 행이 명령을 주인공으로 보여준다 — 등록 스크립트의 친근한 이름과 대비).
        let script = Script(id: newId(), name: trimmed, command: trimmed, cwd: nil)
        oneOffScripts.append(script)
        evictOneOffOverflow()
        launchScript(script, in: project.id, cwd: cwd)
        selectedServiceId = script.id
        openServiceDock(serviceId: script.id, projectId: project.id, tab: .oneoff)
    }

    /// 상한 초과분 정리 — **완료된 오래된 것부터** 세션·run·터미널을 버린다(실행 중은 보존:
    /// "의심되면 안 지운다" — 도는 프로세스를 조용히 죽이지 않는다).
    private func evictOneOffOverflow() {
        while oneOffScripts.count > Self.oneOffHistoryLimit {
            guard let idx = oneOffScripts.firstIndex(where: { scriptRuns[$0.id]?.isRunning != true }) else { break }
            let evicted = oneOffScripts.remove(at: idx)
            evictOneOff(evicted.id, projectId: activeProject?.id)
        }
    }

    /// 일회용 기록 하나를 지운다(행의 🗑) — 세션·run·터미널을 정리한다. 도는 중이면 무시한다
    /// (행에서 🗑을 숨기지만, 판정을 여기서도 좁힌다 — 파괴적 동작은 판정을 좁게).
    func removeOneOff(_ id: String) {
        guard scriptRuns[id]?.isRunning != true else { return }
        oneOffScripts.removeAll { $0.id == id }
        evictOneOff(id, projectId: activeProject?.id)
    }

    /// 일회용 히스토리를 비운다 — 완료분만(실행 중은 남긴다).
    func clearOneOffHistory() {
        let pid = activeProject?.id
        let done = oneOffScripts.filter { scriptRuns[$0.id]?.isRunning != true }
        oneOffScripts.removeAll { scriptRuns[$0.id]?.isRunning != true }
        for s in done { evictOneOff(s.id, projectId: pid) }
    }

    /// 일회용 하나의 세션·run·터미널을 정리한다(오래된 축출·비우기 공통).
    private func evictOneOff(_ id: String, projectId: String?) {
        scriptRuns[id] = nil
        finalLogs[id] = nil
        if selectedServiceId == id { selectedServiceId = nil }
        dropDockTerm(id)
        guard let projectId else { return }
        Task {
            await TmuxService.killScript(projectId: projectId, scriptId: id)
            syncServiceMonitor()
        }
    }

    /// 일회용 → 스크립트 승격. 추가 시트를 명령으로 프리필해 열고(사용자가 이름만 짓게) 스크립트 탭으로.
    /// 원본 히스토리 항목은 남긴다 — 히스토리는 상태가 아니라 기록이다.
    func promoteOneOff(_ id: String) {
        guard let script = oneOffScripts.first(where: { $0.id == id }) else { return }
        scriptAddPrefillCommand = script.command
        requestAddScript()
    }

    /// 잔류(✓/✗ 칩) 확인 — 칩만 내리고 **결과·세션·로그는 남긴다**(종료 로그를 봐야 하므로
    /// 확인이 곧 삭제면 안 된다). 다음 실행이 시작되면 세션이 갈아엎어진다.
    func acknowledgeScriptRun(_ scriptId: String) {
        guard var run = scriptRuns[scriptId], !run.isRunning else { return }
        run.acknowledged = true
        scriptRuns[scriptId] = run
    }

    /// 어느 워크스페이스·프로젝트의 스크립트든 **그리로 데려가서** 도크의 출력(라이브/로그)을 연다
    /// — revealService와 같은 동선·같은 창 규칙.
    func revealScript(scriptId: String) {
        guard let located = trackedLocatedScripts.first(where: { $0.id == scriptId }) else { return }
        if owner(of: located.projectId).isMain {
            if activeId != located.workspaceId { setActiveId(located.workspaceId) }
            if activeProject?.id != located.projectId { setActiveProject(located.projectId) }
        } else {
            windowHost?.raise(.main)
        }
        // 일회용이면 일회용 탭, 등록 스크립트면 스크립트 탭으로 데려간다(선택 항목이 안 보이는 탭 방지).
        let tab: DockTab = oneOffScripts.contains { $0.id == scriptId } ? .oneoff : .scripts
        openServiceDock(serviceId: located.id, projectId: located.projectId, tab: tab)
    }

    /// 폴링 관측 → 레지스트리 병합 + 이번에 **새로 확정된 실패**만 알린다(startServices가 배선).
    /// 판정은 전부 순수(ScriptRun.merging) — 여기는 배관과 알림뿐이다.
    private func mergeScriptObservation(_ observed: [String: ServiceState]) {
        // 기동 중인 스크립트의 관측은 버린다(pendingScriptStarts 주석) — 이전 실행의 pane일 수 있다.
        let settled = observed.filter { !pendingScriptStarts.contains($0.key) }
        let (next, exits) = ScriptRun.merging(runs: scriptRuns, observed: settled,
                                              registered: trackedLocatedScripts, now: Date())
        if next != scriptRuns { scriptRuns = next }
        // (스크립트 종료 로그는 상세가 attach로 얼어붙은 pane을 그대로 보여주므로 텍스트 스냅샷을 안 뜬다 —
        //  종료 로그 텍스트 폴백은 세션이 kill되는 **서비스 중단**에만 필요하고, 그건 stopService가 뜬다.)
        for run in exits where run.isFailure {
            guard case .finished(let code?, _) = run.state else { continue }
            guard let location = located(run.projectId) else { continue }
            // tabId 자리에 스크립트 id — revealActivity가 스크립트 동선(도크)으로 되돌린다(서비스와 동일).
            attention.record(workspaceId: location.workspace.id, projectId: run.projectId,
                             tabId: run.scriptId, kind: .system,
                             title: "\(run.name) 실패 (exit \(code))")
            markProjectBadge(run.projectId)
        }
    }

    /// 등록된 서비스·스크립트가 바뀔 때마다 모니터에 알린다(폴링 대상 갱신). 둘 다 0개면 폴링이 멈춘다.
    /// **일회용 id도 함께 추적**한다 — 폴링 대상에서 빠지면 그 run이 다음 폴에서 관측 없이 증발한다.
    /// (GC 입력 `collectLiveScriptIds`엔 일회용을 넣지 않는다 → 다음 실행 세션에서 자동 청소가 목표.)
    func syncServiceMonitor() {
        let scriptIds = collectLiveScriptIds(in: workspaces).union(oneOffScripts.map(\.id))
        serviceMonitor.sync(services: allServices, scriptIds: scriptIds)
    }

    /// 프로젝트가 사라질 때(프로젝트 닫기·워크스페이스 제거) 그 서비스 프로세스도 함께 죽인다.
    ///
    /// **등록만 지우면 좀비가 된다.** tmux 세션은 muxa와 무관하게 살아남아 포트를 계속 문다 —
    /// 다음 앱 시작의 청소(collectServiceGarbage)까지 남아 있고, 그 사이 `:3000`이 잡혀 있으면
    /// 사용자는 "왜 dev 서버가 안 뜨지"로 시간을 버린다. 사라지는 순간 함께 죽인다.
    /// (호출자는 **정말 제거될 때만** 부른다 — 마지막 하나라 안 닫히는데 서비스만 죽으면 더 나쁘다.)
    private func killServices(of project: Project) {
        let services = project.services ?? []
        guard !services.isEmpty, TmuxService.isAvailable else { return }
        for service in services {
            dropDockTerm(service.id)
            if selectedServiceId == service.id { selectedServiceId = nil }
            Task { await TmuxService.kill(projectId: project.id, serviceId: service.id) }
        }
        // 폴링 대상 갱신은 workspaces가 실제로 줄어든 뒤에 유효하다 — 다음 런루프에 맞춘다.
        Task { @MainActor in syncServiceMonitor() }
    }

    /// 프로젝트가 사라질 때 그 스크립트 세션(실행 중·종료 로그 pane)도 함께 죽인다 — killServices와
    /// 대칭. 프로젝트가 workspaces에서 빠지면 GC가 **모르는 프로젝트**로 보고 보존해 영영 안 정리된다.
    private func killScripts(of project: Project) {
        let scripts = project.scripts ?? []
        guard !scripts.isEmpty, TmuxService.isAvailable else { return }
        for script in scripts {
            dropDockTerm(script.id)
            if selectedServiceId == script.id { selectedServiceId = nil }
            scriptRuns[script.id] = nil
            Task { await TmuxService.killScript(projectId: project.id, scriptId: script.id) }
        }
        Task { @MainActor in syncServiceMonitor() } // killServices와 같은 이유(다음 런루프)
    }

    /// 프로젝트가 사라질 때 그 **터미널** tmux 세션(지속 세션 ∞ 탭·detached)도 함께 죽인다.
    ///
    /// 서비스(`killServices`)와 대칭이다. 스토어를 그냥 버리면 `deinit`은 타이머만 끄고 tmux 세션은
    /// 살아남는데, 프로젝트가 workspaces에서 빠지면 다음 시작의 GC가 **모르는 프로젝트**로 보고 보존해
    /// (`TerminalSession.orphans`) 세션이 영영 정리되지 않는다 — 되찾을 UI도 함께 사라져 순수 누수다.
    /// 프로젝트가 사라지면 reattach 경로가 없으므로, `didCloseTab`이 지키는 "말없이 남기면 유령" 원칙을
    /// 여기서도 지켜 명시적으로 죽인다. 세션명은 (1) 열린 스토어의 라이브 세션 (2) 저장된 레이아웃
    /// (3) detached 복구 목록에서 모은다 — 아직 안 연 프로젝트(lazy)의 세션도 (2)(3)으로 커버된다.
    private func killTerminalSessions(of project: Project) {
        guard TmuxService.isAvailable else { return }
        var names = Set<String>()
        if let store = stores[project.id] { names.formUnion(store.liveTmuxSessionNames) }
        if let layout = savedLayouts[project.id] { names.formUnion(layout.tmuxSessions()) }
        for d in project.detached ?? [] { names.insert(d.session) }
        guard !names.isEmpty else { return }
        for name in names { Task { await TmuxService.kill(session: name) } }
    }

    /// 앱 시작 시 1회 — 알림 배선 + 저장된 서비스 재기동 + 폴링 시작.
    ///
    /// **재기동은 "복원"이지 "자동 실행"이 아니다.** tmux 세션이 살아 있으면 start가 멱등이라 아무 일도
    /// 없고(그게 보통), 앱을 재부팅하거나 tmux 서버가 죽은 뒤에만 실제로 다시 뜬다.
    func startServices() {
        guard TmuxService.isAvailable else { return }
        // 스크립트 관측 배선 — 같은 폴링이 두 축을 다 배달한다. 병합·알림은 한 곳(merge)에 모은다.
        serviceMonitor.onScriptsPoll = { [weak self] observed in
            self?.mergeScriptObservation(observed)
        }
        serviceMonitor.onExit = { [weak self] service, code in
            // "정상 종료(0)는 알리지 않는다"는 판정은 배지·요약·칩과 **같은 한 곳**에서 온다(ServiceState.isFailure).
            guard let self, ServiceState.exited(code: code).isFailure else { return }
            guard let location = locateService(service.id, in: self.workspaces) else { return }
            self.attention.record(workspaceId: location.workspaceId, projectId: location.projectId,
                                  tabId: service.id, kind: .system,
                                  title: "\(service.name) 종료됨 (exit \(code))")
            self.markProjectBadge(location.projectId)
        }
        for ws in workspaces {
            for project in ws.projects {
                for service in project.services ?? [] {
                    // 해석 사슬은 collectAllServices와 같다: 서비스 지정 → 프로젝트 경로 → 워크스페이스 경로.
                    guard let cwd = service.cwd ?? project.path ?? ws.path else { continue }
                    Task {
                        reportServiceStart(await TmuxService.start(service, projectId: project.id, cwd: cwd),
                                           service)
                    }
                }
            }
        }
        syncServiceMonitor()
    }

    // MARK: 서비스 도크의 터미널 — 펼칠 때 attach, 접을 때 버린다

    /// serviceId → attach 터미널. 도크가 열려 있는 동안만 산다.
    @ObservationIgnored private var dockTerms: [String: TermView] = [:]

    /// 재시작 횟수 — 세션이 갈아엎어졌음을 로그 뷰에 알리는 토큰(다시 읽게 한다).
    private(set) var serviceRestartSeq = 0

    /// **살아있는** 서비스의 attach 터미널(없으면 만든다). 죽은 서비스는 터미널이 아니라
    /// 읽기 전용 로그를 보여준다(ServiceLogView) — 죽는 순간 터미널을 갈아끼우면 새 ghostty 서피스가
    /// 빈 화면으로 뜨는 레이스를 밟고, 정작 사인(死因)을 봐야 할 때 아무것도 안 보인다.
    ///
    /// **접을 때 버려도 안전한 이유**: 이 서피스에서 도는 건 `tmux attach` 클라이언트일 뿐이고,
    /// dev 서버는 tmux 서버(ppid=1) 쪽에 있다. 서피스를 해제해도 프로세스는 살아 있으므로
    /// 상태를 유지하려고 숨은 서피스를 붙들 필요가 없다 — 재부착 빈 화면 레이스를 아예 안 밟는다.
    func dockTerm(serviceId: String, projectId: String, cwd: String?) -> TermView {
        if let existing = dockTerms[serviceId] { return existing }
        let attach = TmuxService.attachCommand(projectId: projectId, serviceId: serviceId)
        // **nil을 삼키면 안 된다.** id가 세션명 규약을 벗어나면 붙일 세션이 없어 initialCommand가 비고,
        // 그러면 도크에 **그냥 셸**이 떠서 사용자는 "왜 로그가 안 나오지"로 끝난다(시작도 같은 이유로
        // 실패했을 것이다 — TmuxService.start). 사유를 말한다.
        if attach == nil {
            attention.recordSystem(title: "서비스 로그를 열 수 없습니다 — 서비스 id가 세션명 규약을 벗어납니다 (\(serviceId))")
        }
        // 영속탭과 같은 **exec 경로**(`execCommand`)로 붙인다 — 셸에 `tmux attach`를 타이핑하지 않아
        // 번쩍임이 없고, attach가 끝나면 `exec -l $SHELL`로 셸이 남아 서피스가 비지 않는다.
        let term = TermView(app: app, cwd: cwd, command: attach.map(TerminalSession.execCommand))
        dockTerms[serviceId] = term
        return term
    }

    /// **실행 중인** 스크립트의 attach 터미널 — dockTerm과 같은 수명 규칙(도크가 열려 있는 동안만),
    /// 같은 맵(dockTerms — id는 UUID라 서비스와 충돌하지 않는다). 세션명 규약만 스크립트 축이다.
    func dockScriptTerm(scriptId: String, projectId: String, cwd: String?) -> TermView {
        if let existing = dockTerms[scriptId] { return existing }
        let attach = TmuxService.scriptAttachCommand(projectId: projectId, scriptId: scriptId)
        if attach == nil { // dockTerm과 같은 이유 — nil을 삼키면 "그냥 셸"이 떠서 침묵 실패다
            attention.recordSystem(title: "스크립트 출력을 열 수 없습니다 — 스크립트 id가 세션명 규약을 벗어납니다 (\(scriptId))")
        }
        // 영속탭과 같은 exec 경로 — 번쩍임 없이 attach, 끝나면 셸이 남는다(dockTerm 주석).
        let term = TermView(app: app, cwd: cwd, command: attach.map(TerminalSession.execCommand))
        dockTerms[scriptId] = term
        return term
    }

    /// 도크를 닫는다 — attach 터미널을 전부 버린다(프로세스는 tmux가 계속 붙잡는다).
    func closeServiceDock() {
        showServiceDock = false
        dockProjectId = nil
        dockTerms.removeAll()
    }

    /// 도크를 열고 서비스를 고른다(푸터 칩·팝오버·알림에서 호출).
    /// `projectId` = 그 서비스가 속한 프로젝트(nil이면 메인의 활성 프로젝트 — ⌘J·칩의 기존 동작).
    func openServiceDock(serviceId: String?, projectId: String? = nil, tab: DockTab? = nil) {
        selectedServiceId = serviceId ?? selectedServiceId
        dockProjectId = projectId ?? activeProject?.id
        if let tab { dockTab = tab } // nil = 탭 유지(⌘J 중립 토글). 진입점이 주면 그 탭으로.
        showServiceDock = true
        // 앱보다 오래 사는 tmux 서버에도 보기 옵션(마우스·상태바)을 건다 — 이유는 TmuxService 쪽 주석에.
        Task { await TmuxService.applyDockViewingOptions() }
    }

    /// 도크가 그릴 대상 — 도크를 연 프로젝트(사라졌으면 메인의 활성 프로젝트로 폴백).
    var dockTarget: (workspace: Workspace, project: Project)? {
        if let dockProjectId, let found = located(dockProjectId) { return found }
        guard let ws = activeWorkspace, let project = ws.activeProject else { return nil }
        return (ws, project)
    }

    /// **창 전체**의 서비스 — 소속(워크스페이스·프로젝트)을 달고 온다(푸터 칩·팝오버가 본다).
    /// 왜 프로젝트 단위가 아니라 창 전체인가는 `LocatedService`(Service.swift) 주석에 한 번만 적는다.
    var allLocatedServices: [LocatedService] {
        collectAllServices(in: workspaces)
    }

    /// 어느 워크스페이스·프로젝트의 서비스든 **그리로 데려가서** 로그를 연다.
    /// (팝오버에서 다른 프로젝트의 서비스를 클릭했을 때 — 사용자가 직접 찾아 들어가지 않게.)
    ///
    /// 서비스 도크는 v1에서 **메인 창 전용**이다(dockTerms가 전역 맵이라 두 창이 같은 도크를 열면 TermView를
    /// 쟁탈한다 — 명세 §6). 그래서 분리 창의 서비스라도 로그는 메인에서 열고, 그 프로젝트가 없는
    /// 메인의 좌표는 건드리지 않는다(플레이스홀더로 넘어가지 않게).
    /// 대신 **도크의 스코프를 그 프로젝트로 넘긴다** — 안 그러면 메인의 활성 프로젝트로 도크가 그려져
    /// 사용자가 클릭한 서비스는 목록에 없고 엉뚱한 프로젝트의 로그가 열린다.
    func revealService(_ located: LocatedService) {
        if owner(of: located.projectId).isMain {
            if activeId != located.workspaceId { setActiveId(located.workspaceId) }
            if activeProject?.id != located.projectId { setActiveProject(located.projectId) }
        } else {
            windowHost?.raise(.main)
        }
        openServiceDock(serviceId: located.service.id, projectId: located.projectId)
    }

    /// 도크를 열면서 곧바로 추가 시트를 띄운다(원샷 요청 — 도크가 소비하고 내린다).
    var serviceAddRequested = false

    func requestAddService() {
        dockProjectId = activeProject?.id // 추가는 언제나 메인이 보고 있는 프로젝트에 한다
        showServiceDock = true
        serviceAddRequested = true
    }

    /// 스크립트 추가 시트 원샷 요청 — 이제 **도크가 호스팅**한다(도크는 메인 창이라 `.sheet`가 정상;
    /// 스크립트 팝오버가 별도 NSWindow라 시트를 못 띄우던 제약은 팝오버 폐지로 사라졌다).
    /// 호출처는 스크립트 탭의 ＋ · ⌘K "스크립트 추가" · 일회용 승격(promoteOneOff, 프리필).
    var scriptAddRequested = false
    /// 승격 시 명령을 미리 채워 여는 값(사용자는 이름만 짓는다). nil = 빈 시트. 도크가 소비하고 내린다.
    var scriptAddPrefillCommand: String?

    func requestAddScript() {
        guard activeProject != nil else { return }
        dockProjectId = activeProject?.id
        dockTab = .scripts
        showServiceDock = true
        scriptAddRequested = true
    }

    /// ⌘K "일회용 명령 실행" — 도크 일회용 탭을 열고 입력창에 포커스를 요청한다(등록 프로젝트 불필요 —
    /// 실행 시점에 활성 프로젝트를 대상으로 삼는다).
    func requestRunOneOff() {
        openServiceDock(serviceId: nil, tab: .oneoff)
        oneOffFocusRequested = true
    }

    /// 재시작·제거로 세션이 갈아엎어지면 그 서비스의 터미널을 버린다(옛 세션에 붙은 채 남지 않게).
    /// 로그 뷰도 다시 읽도록 시퀀스를 올린다.
    private func dropDockTerm(_ serviceId: String) {
        dockTerms[serviceId] = nil
        serviceRestartSeq += 1
    }

    /// 좀비 청소 — 등록이 사라졌는데 살아남은 서비스 세션을 죽인다. 앱 시작 시 1회.
    ///
    /// 판정 입력은 **모든 워크스페이스**여야 한다:
    ///  - 서비스: 활성 워크스페이스만 훑으면 다른 워크스페이스의 서비스가 고아로 몰려 죽는다.
    ///  - 프로젝트: 내가 아는 프로젝트의 세션만 판정 대상이다. muxa 인스턴스가 여럿이면 tmux 소켓을
    ///    공유하므로, 이 범위 제한이 없으면 서로의 dev 서버를 죽인다.
    func collectServiceGarbage() {
        guard TmuxService.isAvailable else { return }
        let live = collectLiveServiceIds(in: workspaces)
        let liveScripts = collectLiveScriptIds(in: workspaces)
        let known = collectKnownProjectIds(in: workspaces)
        Task {
            await TmuxService.collectGarbage(liveServiceIds: live, knownProjectIds: known)
            // 스크립트 좀비도 같은 원칙으로 — 등록이 살아 있는 세션(종료 로그 포함)은 보존된다.
            await TmuxService.collectScriptGarbage(liveScriptIds: liveScripts, knownProjectIds: known)
        }
    }

    /// 고아 **터미널** tmux 세션 정리(L3) — 닫힌 탭이 남긴 세션을 죽인다. 복원 직후 1회.
    ///
    /// 보존 목록은 **스냅샷이 참조하는 세션 전부**다(열린 스토어 + 아직 안 연 프로젝트의 저장분).
    /// 열린 탭만 세면 lazy 프로젝트의 셸이 고아로 몰려 죽는다 — 서비스 GC가 "활성 워크스페이스만
    /// 훑으면 안 된다"고 배운 것과 같은 함정이다.
    func collectTerminalSessionGarbage() {
        guard TmuxService.isAvailable else { return }
        var live: Set<String> = []
        // ① 스냅샷이 참조하는 세션 — 열린 탭 + 아직 안 연 프로젝트의 저장분
        for snap in savedLayouts.values { live.formUnion(snap.tmuxSessions()) }
        // ② **백그라운드로 남긴 세션** — 탭이 없다고 죽이면 남긴 의미가 없다(그 안에 빌드가 돌고 있다).
        for ws in workspaces {
            for p in ws.projects { live.formUnion((p.detached ?? []).map(\.session)) }
        }
        let known = collectKnownProjectIds(in: workspaces)
        Task { await TmuxService.collectTerminalGarbage(liveSessionNames: live, knownProjectIds: known) }
    }

    /// 백그라운드 프로젝트에 활동(●)이 있음을 표시. 지금 **어느 창에서든 보고 있는** 활성 프로젝트면
    /// 무시하고, 그 외(백그라운드 워크스페이스의 프로젝트 포함)는 전부 배지한다.
    /// 판정 기준이 메인의 활성 프로젝트 하나였다면, 분리 창에 띄워 놓고 보고 있는 프로젝트에 배지가 붙는다.
    /// stores는 프로젝트 id로 전역 유지되므로 백그라운드 워크스페이스 store의 활동도 여기로 들어온다.
    private func markProjectBadge(_ projectId: String) {
        guard !visibleActiveProjectIds.contains(projectId) else { return }
        insertBadge(projectId)
    }

    /// 앱이 다시 앞으로 나왔다 — **지금 보이는** 활성 프로젝트들의 배지를 해제한다.
    ///
    /// 배지 판정(`markProjectBadge`)은 "앱이 백그라운드면 안 보이는 것"이라 배경에서 끝난 작업에 ●를 단다.
    /// 그런데 돌아왔을 때 지우는 경로가 없으면 **눈앞에서 보고 있는 프로젝트에 배지가 영영 남는다** —
    /// 사용자는 화면에 다 보이는 걸 두고 "아직 나를 기다린다"는 신호를 계속 받는다. 다는 조건과
    /// 지우는 조건이 같은 함수(`visibleActiveProjectIds`)를 봐야 신호가 거짓말하지 않는다.
    func clearVisibleBadges() {
        for projectId in visibleActiveProjectIds { clearBadge(projectId) }
    }

    /// 배지 추가/해제는 이 두 함수로 일원화한다 — 매번 Dock 카운트를 함께 갱신하기 위해.
    private func insertBadge(_ projectId: String) {
        badgedProjects.insert(projectId)
        updateDockBadge()
    }

    /// (창 라우팅(`AppState+Windows`)도 부른다 — 분리 창을 앞으로 올린 것도 "보게 된 것"이다.)
    func clearBadge(_ projectId: String) {
        guard badgedProjects.contains(projectId) else { return }
        badgedProjects.remove(projectId)
        updateDockBadge()
    }

    /// 총 대기 수(배지된 프로젝트 수)를 Dock 아이콘 배지에 반영. 0이면 배지 제거.
    private func updateDockBadge() {
        let count = badgedProjects.count
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    // MARK: 도구 패널 액션 (익스플로러·Git — 영속 없음)

    func toggleExplorer() { selectInspector(.explorer) }
    func toggleGitPanel() { selectInspector(.git) }

    /// 단축키(⌘⇧E/⌘⇧G)가 부르는 창 지역 토글 — 크롬 값의 주인이 창마다 다르다(명세 §6의 비대칭):
    /// 메인은 AppState의 필드, 분리 창은 자기 `ProjectWindow`. 창을 안 보면 분리 창에서 누른 키가
    /// 뒤에 가려진 메인의 패널을 열고 정작 그 창은 아무 반응이 없다.
    func togglePanel(explorer: Bool, in windowId: WindowID) {
        guard !windowId.isMain else {
            explorer ? toggleExplorer() : toggleGitPanel()
            return
        }
        updateWindow(windowId) { window in
            var next = window
            if explorer { next.showExplorer.toggle() } else { next.showGitPanel.toggle() }
            return next
        }
    }
    func setExplorer(_ open: Bool) { if open { openInspector(.explorer) } else if showExplorer { closeInspector() } }
    func setGitPanel(_ open: Bool) { if open { openInspector(.git) } else if showGitPanel { closeInspector() } }

    // MARK: 워크스페이스 액션

    /// **불변: 활성 워크스페이스는 항상 펼쳐진 채로 있다**(포커스한 곳은 프로젝트가 보여야 한다). activeId를
    /// 바꾸는 모든 경로가 이 문 하나로 지나가 펼침 집합에 넣는다 — 어느 한 곳이 빠뜨리는 일이 없게.
    /// **다른 워크스페이스는 접지 않는다**(아코디언 아님 — 여럿이 동시에 펼쳐진 채 유지된다).
    private func focus(_ id: String) {
        activeId = id
        expandedWorkspaces.insert(id)
    }

    func setActiveId(_ id: String) {
        guard activeId != id else { return }
        focus(id)
        // 이 워크스페이스로 넘어와 그 활성 프로젝트를 보게 됐으니 해당 배지 해제.
        if let ws = workspaces.first(where: { $0.id == id }), let pid = ws.activeProject?.id {
            clearBadge(pid)
            // 도크가 열려 있으면 새 워크스페이스의 활성 프로젝트로 따라간다(setActiveProject와 같은 이유).
            if showServiceDock { dockProjectId = pid }
        }
        save()
    }

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        save()
    }

    @discardableResult
    func addWorkspace(path: String?) -> Workspace {
        let ws = createWorkspace(path: path)
        workspaces.append(ws)
        focus(ws.id) // 새 워크스페이스는 활성 + 펼침
        save()
        syncWorktreeMonitor() // 새 repo에 워크트리 감시자를 붙인다
        return ws
    }

    func ensureInitial(path: String?) {
        guard workspaces.isEmpty else { return }
        let ws = createWorkspace(path: path)
        workspaces = [ws]
        focus(ws.id) // 첫 워크스페이스도 활성 + 펼침
        save()
        syncWorktreeMonitor()
    }

    /// 워크스페이스 표시 이름 변경. 빈 이름은 무시(이름 없는 항목은 사이드바에서 식별 불가).
    func renameWorkspace(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateWorkspace(id) { ws in
            var next = ws
            next.name = trimmed
            return next
        }
    }

    /// 워크스페이스 기본 경로 변경 — 경로를 상속하는 프로젝트(path == nil)의 cwd가 바뀐다.
    /// 즉시 반영되는 곳: 파일 익스플로러·Git 패널·**앞으로 여는 터미널**. 이미 떠 있는 PTY는 그 폴더에 남는다
    /// (프로세스의 cwd는 밖에서 못 바꾼다 — 호출부가 사용자에게 이 사실을 알린다).
    /// 이름이 옛 폴더명 그대로였다면(=사용자가 따로 이름을 안 지었다면) 새 폴더명으로 함께 갱신한다.
    func setWorkspacePath(_ id: String, path: String) {
        let pathChanged = workspaces.first(where: { $0.id == id })?.path != path
        updateWorkspace(id) { ws in
            var next = ws
            let wasDefaultName = ws.path.map { ws.name == basename($0) } ?? false
            next.path = path
            if wasDefaultName || ws.path == nil { next.name = basename(path) }
            // 경로를 상속하던 프로젝트의 세션 기준선은 다른 리포의 커밋일 수 있으니 버린다(다음 조회에서 재기록).
            next.projects = ws.projects.map { p in
                guard p.path == nil else { return p }
                var np = p
                np.sessionBaseHead = nil
                return np
            }
            return next
        }
        // 이미 열려 있는 프로젝트의 스토어도 새 시작 폴더를 알아야 한다 — 안 그러면 앞으로 여는 탭까지
        // 옛 폴더에서 열려, 메뉴가 사용자에게 한 약속("앞으로 여는 터미널에 적용")이 거짓이 된다.
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        for project in ws.projects where project.path == nil {
            stores[project.id]?.updateCwd(path)
            // **서비스는 프로세스라 살아있는 세션의 cwd를 밖에서 못 바꾼다** — 새 경로에서 다시 띄운다.
            // 경로가 바뀌면 옛 폴더의 세션은 더는 워크스페이스에 속하지 않는다(예: `/`에서 즉사하던
            // dev 서버가 올바른 폴더로 옮겨 온다). 터미널 cwd 갱신과 대칭. 재시작은 옛 세션을 죽이고
            // 새로 만든다(restartService) — 도는 서비스는 잠깐 끊긴다(경로 이전의 불가피한 대가).
            // 경로가 실제로 바뀔 때만 — 같은 값 재지정으로 서비스를 헛되이 끊지 않는다.
            // **자체 cwd를 지정한 서비스는 건드리지 않는다** — 그 서비스의 실행 폴더는 워크스페이스
            // 경로와 무관하므로, 옮겨 갈 이유도 재시작으로 끊을 이유도 없다.
            if pathChanged {
                for service in project.services ?? [] where service.cwd == nil {
                    restartService(service.id, in: project.id, cwd: path)
                }
            }
        }
        syncWorktreeMonitor() // 경로가 바뀌면 감시 대상 repo도 바뀐다 — 옛 감시자를 떼고 새 repo에 붙인다
    }

    /// 워크스페이스 복제 — 경로·프로젝트 구성만 복제한다(새 id). 터미널 세션·스크롤백은 프로세스라 복제 불가라
    /// 복제본은 빈 터미널로 시작한다. 새 워크스페이스가 곧바로 활성이 된다.
    @discardableResult
    func duplicateWorkspace(_ id: String) -> Workspace? {
        guard let source = workspaces.first(where: { $0.id == id }) else { return nil }
        let projects = source.projects.map { Project(id: newId(), name: $0.name, path: $0.path) }
        guard let first = projects.first else { return nil }
        let copy = Workspace(id: newId(), path: source.path, name: "\(source.name) 복사본",
                             projects: projects, activeProjectId: first.id)
        workspaces.append(copy)
        focus(copy.id) // 복제본도 활성 + 펼침
        save()
        syncWorktreeMonitor() // 복제본 repo에도 감시자를 붙인다
        return copy
    }

    /// 워크스페이스 제거(마지막 하나는 남긴다). 소속 프로젝트의 스토어·저장 레이아웃·배지·**서비스**를
    /// 함께 정리한다.
    func removeWorkspace(_ id: String) {
        guard workspaces.count > 1, let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        for project in workspaces[idx].projects {
            killServices(of: project) // 등록만 지우면 dev 서버가 포트를 문 채 살아남는다
            killScripts(of: project) // 스크립트 세션(실행 중·종료 로그)도 대칭으로
            killTerminalSessions(of: project) // 지속 세션·detached도 함께 — 스토어·레이아웃 버리기 전에
            stores[project.id] = nil
            savedLayouts[project.id] = nil
            clearBadge(project.id)
        }
        var next = workspaces
        next.remove(at: idx)
        workspaces = next
        // 사라진 워크스페이스의 펼침 기록은 함께 버린다(유령 id 누적 방지).
        expandedWorkspaces = SidebarTree.prune(expandedWorkspaces, workspaceIds: next.map(\.id))
        // 사라진 프로젝트를 품고 있던 분리 창도 함께 정리 — 빈 창이 남으면 고아 창이 된다(I5).
        projectWindows = WindowLayout.normalize(projectWindows, projectIds: allProjectIds)
        syncWindows()
        // 활성을 닫았으면 이웃으로 넘어가되 그 이웃도 펼쳐 보여준다(안 그러면 접힌 워크스페이스로 떨어진다).
        if activeId == id { focus(next[min(idx, next.count - 1)].id) }
        save()
        syncWorktreeMonitor() // 사라진 repo의 감시자를 뗀다
    }

    /// 워크스페이스 하나를 불변 갱신한다(id로 지정 — 활성이 아니어도 된다).
    private func updateWorkspace(_ id: String, _ transform: (Workspace) -> Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        var next = workspaces
        next[idx] = transform(workspaces[idx])
        workspaces = next
        save()
    }

    // MARK: 프로젝트 액션 (활성 워크스페이스 대상)

    /// 활성 워크스페이스에서 프로젝트를 전환한다.
    func setActiveProject(_ projectId: String) {
        clearBadge(projectId) // 프로젝트를 보게 됐으니 배지 해제
        updateActiveWorkspace { ws in
            guard ws.projects.contains(where: { $0.id == projectId }) else { return ws }
            var next = ws
            next.activeProjectId = projectId
            return next
        }
        // 서비스 도크가 열려 있으면 새 활성 프로젝트로 따라간다 — 안 그러면 도크(`dockTarget`)가 연 시점
        // 프로젝트에 고정돼, 프로젝트를 바꿔도 서비스 목록·로그·추가 cwd가 예전 경로 그대로다.
        if showServiceDock { dockProjectId = projectId }
    }

    /// 워크스페이스를 지정해 활성 프로젝트를 바꾼다(활성 워크스페이스가 아니어도 된다).
    /// **저장은 호출자 몫** — 창 이동(`moveProjects`)이 여러 워크스페이스를 연달아 고치고 마지막에 한 번 저장한다.
    func setActiveProject(_ projectId: String, inWorkspace wsId: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == wsId }),
              workspaces[idx].projects.contains(where: { $0.id == projectId }) else { return }
        var next = workspaces
        next[idx].activeProjectId = projectId
        workspaces = next
    }

    /// 새 프로젝트(워크트리 등)를 활성 워크스페이스에 추가하고 활성화한다.
    @discardableResult
    func addProject(name: String, path: String?) -> Project? {
        let project = createProject(name: name, path: path)
        updateActiveWorkspace { ws in
            var next = ws
            next.projects.append(project)
            next.activeProjectId = project.id
            return next
        }
        return activeWorkspace == nil ? nil : project
    }

    // MARK: 워크트리 감지 → "추가?" 제안 (D31 · orca 인박스 경량 이식)
    // 감지는 WorktreeMonitor(경계), 제안·baseline·승격은 여기(AppState)가 소유한다.

    /// 워크스페이스 집합이 바뀌면 감시자를 맞춘다(멱등). 세션 변경(add/remove)·startup(뷰 onAppear)에서 부른다.
    func syncWorktreeMonitor() { worktreeMonitor.sync(workspaces) }

    /// 이 워크트리 프로젝트에서 도는 작업이 살아 있는 **다른 프로젝트의 탭**(옛 탭에 갇힌 세션) — 링크 카드(D31)가 읽는다.
    /// 다른 스토어들의 실효 cwd(훅 cwd ?? 셸 pwd — `effectiveCwds`)를 훑어, 이 프로젝트 경로 안에서 도는
    /// 가장 깊은 것을 고른다(매칭은 순수 `WorktreeLink`). 훅 cwd 우선인 이유는 `hasLiveSession` 참조.
    func externalLiveSession(for projectId: String) -> ExternalWorktreeSession? {
        guard let ws = workspace(containing: projectId),
              let project = ws.projects.first(where: { $0.id == projectId }),
              let path = project.path ?? ws.path, !path.isEmpty else { return nil }
        let allPaths = allProjectPaths()
        // 다른 프로젝트에 살아 있는 (tab, pwd) 중 **임자가 이 프로젝트인** 것만 후보로. 임자 판정을 통과했으면
        // 이미 이 경로 안이므로, 여러 개면 **cwd가 가장 깊은** 것(가장 구체적으로 이 워크트리를 파고든 세션)을 고른다.
        let paths = allPaths.map(\.path)
        var best: (originProjectId: String, tabId: TabID, persistent: Bool, depth: Int)?
        for (pid, store) in stores where pid != projectId {
            for (tabId, pwd) in store.effectiveCwds {
                guard let oi = WorktreeLink.owner(pwd: pwd, projectPaths: paths),
                      allPaths[oi].id == projectId else { continue }
                let depth = normalizePath(pwd).count
                if depth > (best?.depth ?? -1) {
                    best = (pid, tabId, store.isPersistent(tabId), depth)
                }
            }
        }
        guard let b = best else { return nil }
        return ExternalWorktreeSession(originProjectId: b.originProjectId,
                                       // self. — 위 guard의 로컬 project(값)가 동명 메서드를 가린다
                                       originName: self.project(b.originProjectId)?.name ?? "다른 프로젝트",
                                       tabId: b.tabId, isPersistent: b.persistent)
    }

    /// 링크 탭 "가져오기"·이동 배너 "옮기기" — 영속(∞) 세션을 원본 프로젝트에서 워크트리 프로젝트로 이식한다.
    /// A에서 tmux 세션을 detach(kill/record 없이)하고 B에서 같은 세션에 attach — **라이브 서피스를 옮기지 않아**
    /// 안전(프로세스는 tmux 서버에 산다). 일반 터미널은 `handOffPersistentTab`이 nil을 줘 무동작.
    /// 가져온 뒤 그 프로젝트로 데려가고, 대상의 링크 탭(안내)은 치운다 — 실물이 도착했다.
    func bringPersistentTab(from originId: String, tabId: TabID, to targetId: String) {
        guard let origin = stores[originId],
              let ws = workspace(containing: targetId),
              let targetProject = ws.projects.first(where: { $0.id == targetId }) else { return }
        // 대상 스토어는 lazy라 **한 번도 안 연 프로젝트면 아직 없다** — 만들어서 받는다(배너에서 바로 옮기는
        // 주 시나리오가 정확히 이 경우다. 없다고 조용히 무시하면 "옮기기가 안 눌린다"로 보인다 — 실측).
        let target = store(for: targetProject, in: ws)
        // 부트스트랩 정리를 이식 **전에** 끝낸다 — ensureInitialTerminal은 자기 시점의 탭 전부를 부트스트랩으로
        // 보고 닫으므로, 이식이 먼저면 방금 옮긴 ∞ 탭이 그 청소에 쓸려 나간다(세션까지 놓친다).
        target.ensureInitialTerminal()
        guard let handed = origin.handOffPersistentTab(tabId) else { return }
        target.reattach(handed)
        target.closeWorktreeLinkTabs()
        setActiveId(ws.id)
        setActiveProject(targetId)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 진행 중인 세션(∞ 탭)이 **다른 프로젝트(워크트리)** 안에서 작업 중이면 그 프로젝트를 이동 대상으로 준다 —
    /// 원본 칸 상단 "옮길까요?" 배너(D31 이동 배지)의 재료. **영속(∞) 탭만** 대상(일반 터미널은 못 옮긴다 — 배너 자체를 안 띄움).
    func worktreeMoveSuggestion(for tabId: TabID, in projectId: String) -> WorktreeMoveSuggestion? {
        guard let store = stores[projectId], store.isPersistent(tabId),
              let cwd = store.effectiveCwds[tabId] else { return nil }
        let all = allProjectPaths()
        guard let oi = WorktreeLink.owner(pwd: cwd, projectPaths: all.map(\.path)),
              all[oi].id != projectId,
              let target = project(all[oi].id) else { return nil }
        return WorktreeMoveSuggestion(targetProjectId: target.id, targetName: target.name)
    }

    /// 전 워크스페이스 프로젝트의 (id, 실효 경로) — 세션 cwd의 임자 판정(`WorktreeLink.owner`) 입력.
    private func allProjectPaths() -> [(id: String, path: String)] {
        workspaces.flatMap { w in w.projects.compactMap { p in (p.path ?? w.path).map { (p.id, $0) } } }
    }

    /// 워크트리 폴더가 사라진 프로젝트를 다시 판정한다(존재 확인=경계, 판정=순수 `DeadWorktree`).
    /// **닫지 않는다** — 살아있는 cc·미저장 작업을 지키려 배지만 갱신하고, 정리는 사용자에게 맡긴다.
    /// FSEvents 변화(`worktreeMonitor.onChange`)·startup·피커 제거에서 부른다.
    func reconcileDeadWorktrees() {
        let fm = FileManager.default
        let next = DeadWorktree.projectIds(in: workspaces) { path in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
        if next != deadWorktreeProjectIds { deadWorktreeProjectIds = next }
    }

    /// 인박스에 "추가?"로 띄울 워크트리 — 감지됨 − (기존 Project ∪ baseline). 뷰가 관측해 렌더한다.
    func worktreeOffers(for workspace: Workspace) -> [GitWorktree] {
        WorktreePromotion.offers(worktrees: worktreeMonitor.detected[workspace.id] ?? [], in: workspace)
    }

    /// 프로젝트의 현재 브랜치(표시용 — 브레드크럼) — `WorktreeMonitor.detected`에서 실효 경로가 일치하는
    /// 워크트리(메인 워킹트리 포함)의 branch를 읽는다. **셸아웃·폴링 없음**: checkout도 `.git` 변화라
    /// FSEvents가 준실시간으로 갱신해 둔다. git 저장소가 아니거나 detached면 nil(표시 안 함).
    func currentBranch(of project: Project, in workspace: Workspace) -> String? {
        guard let path = (project.path ?? workspace.path).map(normalizePath) else { return nil }
        return worktreeMonitor.detected[workspace.id]?
            .first { normalizePath($0.path) == path }?.branch
    }

    /// **muxa 안에서 만든 워크트리는 자동으로 프로젝트가 된다**(D31 보완). 새로 감지된 워크트리 안에
    /// **살아있는 muxa 세션의 cwd**가 있으면(에이전트가 만들고 들어간 것 — 사용자의 의도된 행동) 인박스를
    /// 거치지 않고 조용히 승격한다. 그 신호가 없으면(외부 생성) 기존 "추가?" offer로 남는다 — D31이 막으려던
    /// 놀람·노이즈는 외부 생성의 문제다. `importWorktree`가 baseline을 적재하므로 닫아도 부활하지 않는다.
    /// 트리거: `worktreeMonitor.onChange`(.git 변화) + `onPwdChange`(cd) — 어느 쪽이 늦어도 잡힌다.
    func autoImportWorktrees() {
        for ws in workspaces {
            for wt in worktreeOffers(for: ws) where hasLiveSession(inside: wt.path) {
                importWorktree(wt, in: ws.id)
                // "조용히"는 포커스를 안 뺏는다는 뜻이지 무알림이 아니다 — 인박스에 한 줄 남겨
                // 사이드바를 안 보고 있어도 자동 승격이 일어났음을 뒤늦게라도 알 수 있게 한다(UX 감사 L2).
                attention.recordSystem(title: "워크트리 ‘\(wt.displayName)’을 감지해 프로젝트로 추가했습니다.")
            }
        }
    }

    /// 어느 스토어든 실효 cwd(훅 cwd 우선 ?? 셸 pwd)가 이 경로 안에 있는 라이브 탭이 있는가 —
    /// "muxa에서 만든 워크트리"의 신호. 훅 cwd를 봐야 cc의 EnterWorktree(셸 cd 없음)·∞ 탭(OSC 7 미통과)이 잡힌다.
    private func hasLiveSession(inside path: String) -> Bool {
        stores.values.contains { store in
            store.effectiveCwds.values.contains { pathIsInside($0, root: path) }
        }
    }

    /// "추가" — 워크트리를 Project로 승격하고(포커스는 안 뺏는다 — 조용히 추가) baseline에 적재한다.
    func importWorktree(_ wt: GitWorktree, in workspaceId: String) {
        let project = createProject(name: wt.displayName, path: wt.path)
        updateWorkspace(workspaceId) { ws in
            var next = ws
            next.projects.append(project)
            next.acknowledgedWorktreePaths = Self.acknowledging(ws, path: wt.path)
            return next
        }
    }

    /// "무시" — 승격하지 않고 baseline에만 적재한다(이 워크트리는 다시 제안하지 않는다).
    func dismissWorktree(_ wt: GitWorktree, in workspaceId: String) {
        updateWorkspace(workspaceId) { ws in
            var next = ws
            next.acknowledgedWorktreePaths = Self.acknowledging(ws, path: wt.path)
            return next
        }
    }

    /// baseline에 경로를 더한다(중복 없이 — offer는 Set으로 걸러지지만 저장분을 깔끔히 유지).
    private static func acknowledging(_ ws: Workspace, path: String) -> [String] {
        let current = ws.acknowledgedWorktreePaths ?? []
        let norm = normalizePath(path) // offers가 정규화 비교하므로 여기서도 정규화로 중복 판정(뒤슬래시 변형 누적 방지)
        return current.contains { normalizePath($0) == norm } ? current : current + [path]
    }

    /// 프로젝트 표시 이름 변경(어느 워크스페이스든). 빈 이름은 무시.
    func renameProject(_ projectId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProject(projectId) { p in
            var next = p
            next.name = trimmed
            return next
        }
    }

    /// 프로젝트를 앞/뒤로 순환 전환한다(⌘⇧] / ⌘⇧[) — **키를 친 창 안에서만**.
    ///
    /// 메인: 활성 워크스페이스의 프로젝트를 돌되 **분리된 것은 건너뛴다**(다른 창이 그리고 있어
    /// 넘어가 봐야 플레이스홀더만 보인다). 분리 창: 그 창이 품은 프로젝트 목록 안에서 돈다 —
    /// 메인의 좌표를 건드리면 보이지도 않는 창의 활성 프로젝트가 조용히 바뀐다.
    @discardableResult
    func cycleProject(forward: Bool, in windowId: WindowID = .main) -> Bool {
        if let window = projectWindows.first(where: { $0.id == windowId }) {
            guard let next = WindowLayout.nextProject(from: window.activeProjectId,
                                                      in: window.projectIds, forward: forward)
            else { return false }
            setActiveProject(next, inWindow: windowId)
            return true
        }
        guard let ws = activeWorkspace,
              let next = WindowLayout.nextMainProject(from: ws.activeProjectId, in: ws.projects.map(\.id),
                                                      forward: forward, windows: projectWindows)
        else { return false }
        setActiveProject(next)
        return true
    }

    /// 프로젝트를 닫는다(마지막 하나는 남긴다). 활성이면 인접 프로젝트로 전환.
    /// 닫히는 프로젝트의 **서비스 프로세스도 함께 죽인다**.
    func closeProject(_ projectId: String) {
        // 분리 창에 있던 프로젝트면 **먼저** 메인으로 되돌린다 — 창을 정리한 뒤에 지워야 그 창이
        // 유령으로 남지 않는다(파괴 순서: 창 → 프로젝트). 확인은 호출부(ProjectClose)가 이미 받았다.
        if !self.owner(of: projectId).isMain { moveProjects([projectId], to: .main) }
        // **소속 워크스페이스를 id로 되짚는다** — 사이드바 트리는 비활성 워크스페이스의 프로젝트도
        // 그리므로(✕·우클릭 닫기), 활성 워크스페이스만 보면 그 클릭이 조용히 씹힌다.
        guard let owner = workspace(containing: projectId) else { return }
        // **정말 닫힐 때만** 서비스를 죽인다 — 마지막 하나는 안 닫히는데(아래 guard) 서비스만 죽으면
        // 프로젝트는 그대로인 채 dev 서버만 사라진다.
        if owner.projects.count > 1,
           let project = owner.projects.first(where: { $0.id == projectId }) {
            killServices(of: project)
            killScripts(of: project)
            killTerminalSessions(of: project) // 스토어·레이아웃을 버리기 전에 — 세션명을 여기서 읽는다
        }
        stores[projectId] = nil
        savedLayouts[projectId] = nil
        clearBadge(projectId)
        updateWorkspace(owner.id) { ws in
            guard ws.projects.count > 1,
                  let idx = ws.projects.firstIndex(where: { $0.id == projectId }) else { return ws }
            var next = ws
            next.projects.remove(at: idx)
            if next.activeProjectId == projectId {
                next.activeProjectId = next.projects[min(idx, next.projects.count - 1)].id
            }
            return next
        }
        // 닫힌 프로젝트가 분리 창에 있었다면 그 창에서도 빼낸다(빈 창은 사라진다 — I5).
        projectWindows = WindowLayout.normalize(projectWindows, projectIds: allProjectIds)
        syncWindows()
        // 닫힌 뒤 새로 활성화된 프로젝트도 배지 클리어(사용자가 보게 됐으니) — 유령 배지 방지.
        if let newActive = activeProject?.id { clearBadge(newActive) }
    }

    /// 프로젝트 하나를 불변 갱신한다(어느 워크스페이스든 — 소속을 id로 찾는다). 새 배열로 교체.
    private func updateProject(_ projectId: String, _ transform: (Project) -> Project) {
        guard let wsIdx = workspaces.firstIndex(where: { $0.projects.contains { $0.id == projectId } }),
              let pIdx = workspaces[wsIdx].projects.firstIndex(where: { $0.id == projectId }) else { return }
        var nextWorkspaces = workspaces
        var ws = nextWorkspaces[wsIdx]
        var projects = ws.projects
        projects[pIdx] = transform(projects[pIdx])
        ws.projects = projects
        nextWorkspaces[wsIdx] = ws
        workspaces = nextWorkspaces
        save()
    }

    /// 활성 워크스페이스를 불변 갱신한다(immutable — 새 배열로 교체).
    private func updateActiveWorkspace(_ transform: (Workspace) -> Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == activeId }) else { return }
        var next = workspaces
        next[idx] = transform(workspaces[idx])
        workspaces = next
        save()
    }

    // MARK: 영속 (메타데이터 + 프로젝트별 분할 트리)

    /// **테스트가 왕복(인코딩→디코딩)을 못 박기 위해 internal** — CodingKeys 누락처럼
    /// "인코딩은 되는데 저장이 안 되는" 버그는 타입을 감추면 못 잡는다(StateLoad를 뽑은 것과 같은 논리).
    struct Persisted: Codable {
        /// 현재 스냅샷 스키마 버전. 향후 마이그레이션·비대화 방어의 기준점.
        /// version 필드가 없던 구 state.v4.json은 디코드 시 0으로 채워진다(pre-version).
        static let currentVersion = 1

        var version: Int
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
        var layouts: [String: PaneSnapshot]? // 프로젝트 id → 통합 스냅샷(터미널·문서·diff 전부).
        var explorerWidth: Double? // 도구 패널 폭(리사이즈, 나중에 추가된 필드라 옵셔널 하위호환).
        var gitPanelWidth: Double?
        var serviceDockWidth: Double? // 서비스 서랍 폭(나중에 추가된 필드라 옵셔널 하위호환).
        var showExplorer: Bool? // 도구 패널 열림 상태(나중에 추가된 필드라 옵셔널 하위호환).
        var showGitPanel: Bool?
        /// 사이드바에서 펼쳐 둔 워크스페이스 id들(나중에 추가된 필드라 옵셔널 하위호환).
        /// **Set이 아니라 정렬된 배열로 저장한다** — Set은 JSON 순서가 매번 달라져 파일이 무의미하게 뒤바뀐다.
        var expandedWorkspaces: [String]?
        /// **접어 둔** 에이전트 목록의 프로젝트 id들(나중에 추가된 필드라 옵셔널 하위호환 —
        /// 기본이 펼침이라 접은 것만 저장한다. 정렬 배열 저장 이유는 expandedWorkspaces와 동일).
        var collapsedAgentLists: [String]?
        /// 분리 창 목록(나중에 추가된 필드라 옵셔널 하위호환 — 구 저장분은 nil = 분리 창 없음).
        ///
        /// **currentVersion을 올리지 않는다**: version은 지금 디코드만 되고 `apply()`가 읽지 않으며,
        /// 이 필드는 순수 가산이라 구 저장분이 그대로 로드된다. 새 저장분을 구 빌드가 읽어도 미지 키는 무시된다.
        /// 어떤 모양이 들어와도 `WindowLayout.normalize`가 복구하므로 마이그레이션 훅이 필요 없다.
        var windows: [ProjectWindow]?

        /// 디코드 중 버려진 프로젝트 id(손상 스냅샷). 디스크에 쓰지 않는 부산물이라 CodingKeys에서 제외한다.
        var droppedLayouts: [String] = []

        private enum CodingKeys: String, CodingKey {
            case version, workspaces, activeId, sidebarMode, layouts
            case explorerWidth, gitPanelWidth, serviceDockWidth, showExplorer, showGitPanel
            case expandedWorkspaces, collapsedAgentLists, windows
        }

        init(workspaces: [Workspace], activeId: String, sidebarMode: SidebarMode,
             layouts: [String: PaneSnapshot]?, explorerWidth: Double?, gitPanelWidth: Double?,
             serviceDockWidth: Double?,
             showExplorer: Bool?, showGitPanel: Bool?, expandedWorkspaces: [String]?,
             collapsedAgentLists: [String]? = nil,
             windows: [ProjectWindow]? = nil,
             version: Int = currentVersion) {
            self.version = version
            self.workspaces = workspaces; self.activeId = activeId; self.sidebarMode = sidebarMode; self.layouts = layouts
            self.explorerWidth = explorerWidth; self.gitPanelWidth = gitPanelWidth
            self.serviceDockWidth = serviceDockWidth
            self.showExplorer = showExplorer; self.showGitPanel = showGitPanel
            self.expandedWorkspaces = expandedWorkspaces
            self.collapsedAgentLists = collapsedAgentLists
            self.windows = windows
        }

        // layouts는 **프로젝트별로 격리 디코드**한다(LenientLayouts) — 스냅샷 하나가 손상돼도 나머지
        // 프로젝트는 살린다. 이전엔 통짜 `try?`라 하나가 깨지면 전 프로젝트 레이아웃이 조용히 사라졌다.
        // version은 나중에 추가된 필드라 decodeIfPresent로 하위호환(구 데이터=0).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
            workspaces = try c.decode([Workspace].self, forKey: .workspaces)
            activeId = try c.decode(String.self, forKey: .activeId)
            sidebarMode = try c.decode(SidebarMode.self, forKey: .sidebarMode)
            let lenient = try? c.decodeIfPresent(LenientLayouts.self, forKey: .layouts)
            layouts = lenient?.layouts
            droppedLayouts = lenient?.dropped ?? []
            explorerWidth = try c.decodeIfPresent(Double.self, forKey: .explorerWidth)
            gitPanelWidth = try c.decodeIfPresent(Double.self, forKey: .gitPanelWidth)
            serviceDockWidth = try c.decodeIfPresent(Double.self, forKey: .serviceDockWidth)
            showExplorer = try c.decodeIfPresent(Bool.self, forKey: .showExplorer)
            showGitPanel = try c.decodeIfPresent(Bool.self, forKey: .showGitPanel)
            expandedWorkspaces = try c.decodeIfPresent([String].self, forKey: .expandedWorkspaces)
            collapsedAgentLists = try c.decodeIfPresent([String].self, forKey: .collapsedAgentLists)
            windows = try c.decodeIfPresent([ProjectWindow].self, forKey: .windows)
        }
    }

    // 워크스페이스 보존, layouts만 통합 스냅샷으로 관대 디코드. muxa 베이스 경로는 단일 소유자 재사용.
    private static let fileURL = MuxaSupportDir.url.appendingPathComponent("state.v4.json")
    /// 마지막으로 **정상 로드에 성공한** 상태의 사본. 시작 시 1회만 갱신하므로(§load) 세션 중 저장이
    /// 손상돼도 직전 정상 세션으로 되돌아갈 수 있다. 매 save마다 복사하면 손상본이 백업까지 덮는다.
    private static let backupURL = MuxaSupportDir.url.appendingPathComponent("state.v4-previous.json")

    /// 상태 저장. 기본은 **메타데이터만**(레이아웃 구조·선택·경로) — 패널 토글·활성 전환 등 잦은 저장이
    /// 열린 모든 터미널의 스크롤백을 매번 리드백·재기록하지 않게 한다. 무거운 스크롤백 캡처는
    /// `captureScrollback: true`(종료 시 endSession)에서만 — 복원 시점에만 최신 화면이 필요하기 때문이다.
    func save(captureScrollback: Bool = false) {
        flushPendingFrames() // 드래그 중 쌓아 둔 창 좌표를 여기서 한 번에 모델로(뷰 무효화 1회)
        // 인스턴스화된 스토어(=열린 프로젝트)의 현재 레이아웃을 통합 스냅샷으로 반영. 빈 스토어는 스킵.
        for (projectId, store) in stores where !store.controller.allTabIds.isEmpty {
            savedLayouts[projectId] = store.snapshot(captureScrollback: captureScrollback)
        }
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode,
                                 layouts: savedLayouts, explorerWidth: Double(explorerWidth),
                                 gitPanelWidth: nil, // 인스펙터가 폭을 통일(explorerWidth) — 레거시 필드는 안 쓴다
                                 serviceDockWidth: Double(serviceDockWidth),
                                 showExplorer: showExplorer, showGitPanel: showGitPanel,
                                 expandedWorkspaces: expandedWorkspaces.sorted(),
                                 collapsedAgentLists: collapsedAgentLists.sorted(),
                                 windows: projectWindows)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // **저장 실패를 삼키지 않는다.** 디스크가 가득 차거나(원자적 쓰기는 임시 파일을 쓰므로 용량을
        // 2배 요구한다) 저장소 권한이 깨지면 조용히 실패해, 다음 실행에서 사용자가 몇 시간짜리 레이아웃을
        // 잃고 이유를 모른다. 로드는 손상을 인박스로 표면화하는데(restoreWarnings) 쓰기만 침묵이었다.
        // save()는 잦게 불리므로 **연속 실패는 1회만** 알린다(복구되면 플래그를 내린다).
        do {
            try data.write(to: Self.fileURL, options: .atomic)
            saveFailed = false
        } catch {
            if !saveFailed {
                attention.recordSystem(title: "세션 저장 실패 — \(error.localizedDescription)")
            }
            saveFailed = true
        }
    }

    /// 직전 저장이 실패했는가 — 같은 실패를 매 저장마다 인박스에 쌓지 않기 위한 1회성 플래그.
    private var saveFailed = false

    /// 분리 창 프레임 저장 디바운스(trailing 0.5s) — 창을 끄는 동안 `windowDidMove`가 초당 수십 번 온다.
    ///
    /// **leading-edge 억제(`SignalCoalescer`)를 쓰면 안 된다** — 그건 첫 신호만 통과시키므로
    /// 드래그가 **끝난 자리**(사용자가 원한 좌표)가 버려진다. 마지막 신호가 이겨야 한다.
    func saveDebounced() {
        frameSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        frameSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.frameSaveDelay, execute: work)
    }

    /// 복원 중 발생한 유실 — 시작 직후 인박스에 표면화한다(beginSession). 조용한 유실은 금지.
    private var restoreWarnings: [String] = []

    /// 세션 상태를 불러온다. 손상 시 2단 폴백: primary → backup(직전 정상 세션) → 빈 상태.
    /// **판정은 `StateLoad`(순수)가**, 파일 읽기·쓰기만 여기서 한다.
    func load() {
        let primary = Self.read(Self.fileURL)
        let backup = Self.read(Self.backupURL)
        let decision = StateLoad.choose(primary: primary.state, backup: backup.state)

        switch decision.source {
        case .primary:
            if let snapshot = primary.snapshot { apply(snapshot) }
            // 정상 로드분을 백업으로 남긴다(세션당 1회) — 이후 저장이 깨져도 여기로 돌아온다.
            if decision.refreshBackup, let data = primary.data {
                try? data.write(to: Self.backupURL, options: .atomic)
            }
        case .backup:
            // 백업은 **덮어쓰지 않는다** — 유일한 복구 경로다.
            if let snapshot = backup.snapshot { apply(snapshot) }
        case .none:
            break
        }
        restoreWarnings.append(contentsOf: decision.warnings)
    }

    /// 파일 하나를 읽고 디코드까지 시도한다(경계). 결과를 순수 판정에 넘길 형태로 돌려준다.
    private static func read(_ url: URL) -> (state: StateLoad.FileState, data: Data?, snapshot: Persisted?) {
        guard let data = try? Data(contentsOf: url) else { return (.missing, nil, nil) }
        guard let snapshot = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return (.corrupt, data, nil)
        }
        return (.valid, data, snapshot)
    }

    private func apply(_ snapshot: Persisted) {
        workspaces = snapshot.workspaces
        activeId = snapshot.activeId
        sidebarMode = snapshot.sidebarMode
        // 활성은 펼친 채로 시작(구 저장분엔 활성이 집합에 없으므로 마이그레이션 겸함). 사라진 id는 걸러낸다.
        // (workspaces·activeId 대입 **뒤에** 와야 한다 — 유효 id 목록·활성에 의존한다.)
        expandedWorkspaces = SidebarTree.restore(saved: snapshot.expandedWorkspaces,
                                                 activeId: activeId,
                                                 workspaceIds: snapshot.workspaces.map(\.id))
        // 접힌 에이전트 목록 — 사라진 프로젝트 id는 걸러낸다(유령 누적 방지). nil(구 저장분)=전부 펼침.
        collapsedAgentLists = Set(snapshot.collapsedAgentLists ?? []).intersection(allProjectIds)
        if let w = snapshot.explorerWidth { explorerWidth = Self.clampPanelWidth(CGFloat(w)) }
        if let w = snapshot.serviceDockWidth { serviceDockWidth = Self.clampServiceDockWidth(CGFloat(w)) }
        if let open = snapshot.showExplorer { showExplorer = open }
        if let open = snapshot.showGitPanel { showGitPanel = open }
        // 우측 슬롯은 하나(단일 슬롯 인스펙터) — 구버전 스냅샷은 탐색기+Git을 동시에 열어 뒀을 수 있으니
        // 상호배타로 정규화한다(탐색기 우선). 알림·설정 탭은 영속하지 않아 재시작 시 항상 닫힘.
        if showExplorer && showGitPanel { showGitPanel = false }
        // 저장분이 어떤 모양이든(유령 프로젝트·중복·빈 창) 신뢰 가능한 배치로 되돌린다 — clampAll과 같은 성격.
        // (workspaces 대입 **뒤에** 와야 한다 — 아는 프로젝트 id 목록에 의존한다.)
        projectWindows = WindowLayout.normalize(snapshot.windows, projectIds: allProjectIds)
        // 복원 직전 상한·손상 방어를 통과시킨다(순수 함수). 비대·변조된 스냅샷의 복원 폭주를 막는다.
        savedLayouts = SnapshotSanitize.clampAll(snapshot.layouts ?? [:])
        if !snapshot.droppedLayouts.isEmpty {
            restoreWarnings.append("레이아웃 \(snapshot.droppedLayouts.count)개를 불러오지 못했습니다(손상).")
        }
    }

    // MARK: 스크롤백 파일 GC (복원 시 새 tabId 발급으로 남는 고아 파일 정리 — 디스크 누수 방지)

    /// 세션 복원이 끝난 뒤 호출 — 유효 tabId 집합이 확정된 안전 시점에 고아 스크롤백 파일을 정리한다.
    /// 유효 집합 = (1) 열린 스토어의 살아있는 tabId + (2) savedLayouts 스냅샷이 참조하는 파일 경로.
    /// lazy 미개방 프로젝트의 스크롤백은 (2)로 보존되고, 어디에도 없고 유예를 넘긴 파일만 지운다(안전 최우선).
    func collectScrollbackGarbage() {
        var referenced: Set<String> = []
        for snap in savedLayouts.values { referenced.formUnion(snap.scrollbackPaths()) }
        var live: Set<String> = []
        for store in stores.values {
            for tabId in store.controller.allTabIds { live.insert(tabId.uuid.uuidString) }
        }
        ScrollbackStore.collectGarbage(liveTabIds: live, referencedPaths: referenced)
    }

    // MARK: 세션 수명 (크래시 마커 — 더티 종료 감지)

    /// 직전 실행이 더티(크래시/강제종료) 종료였는지. 시작 시 beginSession이 판정해 넣는다.
    /// 지금은 노출만 하고 복구 배너·자동 resume 연동은 후속 단계가 담당한다.
    private(set) var lastLaunchWasDirty = false

    /// 세션 시작 표시 — 크래시 마커를 arm하고 직전 더티 여부를 기록한다. AppDelegate가 시작 시 1회 호출.
    /// 더티(비정상 종료)였으면 인박스에 시스템 항목을 1회 남긴다(사용자에게 "복원됐다"를 표면화). 재개 연동은
    /// store가 lastLaunchWasDirty를 받아 재개 전략(ResumeStrategy)으로 배너 강조/자동 여부를 정한다.
    func beginSession() {
        lastLaunchWasDirty = CrashMarker.detectAndArm()
        if lastLaunchWasDirty {
            attention.recordSystem(title: "직전에 비정상 종료됐습니다 — 세션을 복원했습니다.")
        }
        // load()가 모은 유실을 여기서 표면화한다(인박스가 준비된 시점). 조용히 사라지게 두지 않는다.
        for warning in restoreWarnings { attention.recordSystem(title: warning) }
        restoreWarnings = []
    }

    /// 세션 정상 종료 — 마지막 레이아웃을 저장하고 크래시 마커를 지운다(disarm).
    /// applicationWillTerminate가 호출한다. 이 경로를 못 타면(크래시) 마커가 남아 다음 시작에 더티로 잡힌다.
    func endSession() {
        save(captureScrollback: true) // 종료 시 1회만 스크롤백을 최신 화면으로 갱신 — 복원이 이걸 재출력한다
        CrashMarker.disarm()
    }
}

// MARK: - 시스템 경로 (Rust home_dir/current_dir 대체)

enum SystemPaths {
    static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static var currentDir: String? {
        FileManager.default.currentDirectoryPath
    }
}

#if DEBUG
// MARK: - 데모 스크린샷 시드 (MUXA_DEMO) — 같은 파일이라 private(set) 세팅 가능
extension AppState {
    /// 스크린샷 추출용 리치 상태를 코드로 심는다: 워크스페이스 3 × 프로젝트 2, 다양한 에이전트 상태,
    /// 서비스·스크립트 상태, 분할 레이아웃, 트랜스크립트. tmux·라이브 훅 없이 GUI 조작 없이.
    /// `scripts/demo/make-demo.sh`가 만든 ~/muxa-demo 리포·트랜스크립트를 참조한다.
    func seedDemo() {
        let demo = NSHomeDirectory() + "/muxa-demo"
        let tr = demo + "/.transcripts/"
        func t(_ n: String) -> String { tr + n + ".ans" }
        let muxaRoot = AppInfo.worktreeRoot ?? demo + "/webapp"

        // ── 데이터: 워크스페이스 3 × 프로젝트 2 ──
        let p1a = Project(id: "p-webapp-main", name: "메인", path: nil,
                          services: [Service(id: "svc-web", name: "web", command: "pnpm dev"),
                                     Service(id: "svc-api", name: "api", command: "pnpm --filter api dev"),
                                     Service(id: "svc-worker", name: "worker", command: "pnpm worker")],
                          scripts: [Script(id: "scr-build", name: "build", command: "pnpm build"),
                                    Script(id: "scr-test", name: "test", command: "pnpm test")])
        let p1b = Project(id: "p-webapp-feat", name: "feat/checkout", path: demo + "/webapp")
        let ws1 = Workspace(id: "ws-webapp", path: demo + "/webapp", name: "webapp",
                            projects: [p1a, p1b], activeProjectId: p1a.id)

        let p2a = Project(id: "p-muxa-main", name: "메인", path: nil)
        let p2b = Project(id: "p-muxa-docs", name: "docs", path: muxaRoot + "/docs")
        let ws2 = Workspace(id: "ws-muxa", path: muxaRoot, name: "muxa",
                            projects: [p2a, p2b], activeProjectId: p2a.id)

        let p3a = Project(id: "p-api-main", name: "메인", path: nil,
                          services: [Service(id: "svc-api-main", name: "api", command: "go run .")])
        let p3b = Project(id: "p-api-feat", name: "feat/auth", path: demo + "/api-server")
        let ws3 = Workspace(id: "ws-api", path: demo + "/api-server", name: "api-server",
                            projects: [p3a, p3b], activeProjectId: p3a.id)

        workspaces = [ws1, ws2, ws3]
        activeId = ws1.id
        expandedWorkspaces = [ws1.id, ws2.id, ws3.id]
        sidebarMode = .expanded

        // ── 서비스·스크립트 런타임 상태(tmux 없이) ──
        serviceMonitor.demoSeed(
            states: ["svc-web": .running, "svc-api": .running, "svc-worker": .exited(code: 1),
                     "svc-api-main": .running],
            ports: ["svc-web": 3000, "svc-api": 8787, "svc-api-main": 8080])
        scriptRuns = [
            "scr-build": ScriptRun(scriptId: "scr-build", projectId: p1a.id, name: "build",
                                   startedAt: Date(timeIntervalSinceNow: -8.2),
                                   state: .finished(code: 0, duration: 8.2)),
            "scr-test": ScriptRun(scriptId: "scr-test", projectId: p1a.id, name: "test",
                                  startedAt: Date(timeIntervalSinceNow: -14), state: .running)
        ]

        // ── 활성: webapp/메인 — 3칸 분할(작업중 · 대기 · 완료) ──
        let s1 = store(for: p1a, in: ws1)
        s1.demoSeedLayout {
            let root = s1.demoFocusedPane
            s1.demoTerminal(inPane: root, title: "claude", transcript: t("working"), status: .working)
            let right = s1.demoSplit(.horizontal, title: "claude", transcript: t("waiting"),
                                     status: .waiting, from: root, divider: 0.54)
            s1.demoSplit(.vertical, title: "claude", transcript: t("done"),
                         status: .done, from: right, divider: 0.5)
            if let root { s1.demoFocus(root) }
        }

        // ── 나머지 프로젝트 — 사이드바 상태 다양화(1~2 탭) ──
        func seedSimple(_ p: Project, in ws: Workspace, title: String,
                        transcript: String?, status: NotifyState?,
                        second: (String, String?)? = nil) {
            let s = store(for: p, in: ws)
            s.demoSeedLayout {
                let root = s.demoFocusedPane
                s.demoTerminal(inPane: root, title: title, transcript: transcript, status: status)
                if let (t2, tr2) = second {
                    s.demoTerminal(inPane: root, title: t2, transcript: tr2, status: nil)
                }
            }
        }
        seedSimple(p1b, in: ws1, title: "claude", transcript: t("api-working"), status: .working)
        seedSimple(p2a, in: ws2, title: "claude", transcript: t("done"), status: .done,
                   second: ("zsh", t("zsh")))
        seedSimple(p2b, in: ws2, title: "zsh", transcript: t("zsh"), status: nil)
        seedSimple(p3a, in: ws3, title: "claude", transcript: t("api-working"), status: .working)
        seedSimple(p3b, in: ws3, title: "claude", transcript: t("waiting"), status: .waiting)

        // 주의 큐 카드(사이드바 최상단 로즈 ⏸ 카드)가 뜨도록 대기 프로젝트에 배지를 심는다 —
        // waitingQueue = SidebarTree.allWaiting(badged:) 기반이라 agentActivity만으론 안 뜬다.
        badgedProjects = [p1a.id, p3b.id]

        // ── 장면 선택(MUXA_DEMO_SCENE) — 관측 지점을 바꿔 여러 상황을 뽑는다 ──
        switch ProcessInfo.processInfo.environment["MUXA_DEMO_SCENE"] ?? "split" {
        case "git":     // webapp: 실제 git 변경 + 커밋 패널
            activeId = ws1.id
            showGitPanel = true
        case "viewer":  // muxa: 렌더된 문서 뷰어
            activeId = ws2.id
            _ = store(for: p2a, in: ws2).openFile(muxaRoot + "/docs/ARCHITECTURE.md")
        case "explorer": // muxa: 파일 익스플로러
            activeId = ws2.id
            showExplorer = true
        case "diff":    // webapp: diff 탭
            activeId = ws1.id
            _ = store(for: p1a, in: ws1).openFile(demo + "/webapp/src/config.ts")
        default:        // split — 3분할 히어로
            activeId = ws1.id
        }

        save()
    }
}
#endif
