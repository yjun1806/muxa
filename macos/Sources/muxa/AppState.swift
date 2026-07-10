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

    /// 백그라운드 활동(●)이 있는 프로젝트 id들(A). ProjectTabBar가 관측해 배지를 그린다.
    private(set) var badgedProjects: Set<String> = []

    /// 놓친 주의 이력(알림 인박스). 배지가 붙는 순간마다 한 건씩 쌓인다 — 배지는 "지금 상태",
    /// 이건 "자리 비웠다 돌아왔을 때의 복구 동선". 상단바 벨 팝오버가 관측해 렌더한다.
    let attention = AttentionLog()

    /// 도구 패널 표시 상태(B). 기본 닫힘 — 세션 영속 대상 아님(Persisted에 안 넣는다).
    /// 상단바 토글 버튼·단축키(⌘⇧E/⌘⇧G)·알림이 이 상태를 연다.
    var showExplorer = false
    var showGitPanel = false

    @ObservationIgnored private let app: ghostty_app_t
    /// muxa 설정(`~/.config/muxa/config`) — 시작 시 1회 로드해 주입. 기본 사이드바 모드·완료 배지 임계 등. (DESIGN 4.6)
    @ObservationIgnored let config: MuxaConfig
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
    }

    /// 훅 알림 리스너를 켜고 라우팅 콜백을 건다. AppDelegate가 앱 시작 시 1회 호출.
    func startNotifyServer() {
        notifyServer.onMessage = { [weak self] msg in
            MainActor.assumeIsolated { self?.routeNotify(msg) }
        }
        notifyServer.start()
    }

    /// 훅 메시지를 tabId 소유 store로 라우팅한다. 어느 store가 그 탭을 가졌는지는 순회로 찾는다
    /// (stores는 프로젝트별이고 탭 수가 적어 순회로 충분). 소유 store가 배지·알림을 결정한다.
    private func routeNotify(_ msg: NotifyMessage) {
        guard let uuid = UUID(uuidString: msg.tabId) else { return }
        let tabId = TabID(uuid: uuid)
        for store in stores.values {
            if store.deliverNotify(tabId: tabId, state: msg.state, title: msg.title, body: msg.body) { break }
        }
    }

    // MARK: 알림 → 원클릭 검토 동선 (배지·시스템 알림 클릭)

    /// 스토어(프로젝트)가 요청한 데스크톱 알림에 라우팅 컨텍스트를 붙여 발사한다.
    /// 워크스페이스 id는 프로젝트 소속으로 파생(단일 진실 원천) — 스토어는 몰라도 된다.
    private func emitNotification(projectId: String, tabId: TabID, title: String, body: String) {
        let workspaceId = workspaces.first { $0.projects.contains { $0.id == projectId } }?.id ?? ""
        let context = NotifyContext(workspaceId: workspaceId, projectId: projectId, tabId: tabId.uuid.uuidString)
        NotificationService.shared.notify(title: title, body: body, context: context)
    }

    /// 배지가 붙는 순간 인박스 이력에 한 건 기록한다. 워크스페이스 id는 프로젝트 소속으로 파생(단일 진실 원천).
    private func recordAttention(projectId: String, tabId: TabID, kind: AttentionKind, title: String) {
        let workspaceId = workspaces.first { $0.projects.contains { $0.id == projectId } }?.id ?? ""
        attention.record(workspaceId: workspaceId, projectId: projectId,
                         tabId: tabId.uuid.uuidString, kind: kind, title: title)
    }

    /// 인박스 항목 클릭 → 그 칸으로 점프(원클릭 검토 동선 재사용). 소속이 사라진 항목이면 무동작.
    func revealAttention(_ entry: AttentionEntry) {
        revealActivity(projectId: entry.projectId, tabId: entry.tabId)
    }

    /// 인박스 항목 위치 라벨 — "워크스페이스 · 프로젝트". 소속을 못 찾으면 빈 문자열.
    func attentionLocationLabel(projectId: String) -> String {
        guard let ws = workspaces.first(where: { $0.projects.contains { $0.id == projectId } }),
              let p = ws.projects.first(where: { $0.id == projectId }) else { return "" }
        return "\(ws.name) · \(p.name)"
    }

    /// 배지·시스템 알림 클릭의 공통 착지점 — 대상 프로젝트로 이동 + Git 패널 오픈 + (있으면) 그 탭 선택 + 앱 활성화.
    /// 배지 클릭·알림 클릭이 이 한 메서드를 공유한다("원클릭 검토" 동선의 단일 구현).
    func revealActivity(projectId: String, tabId: String? = nil) {
        guard let ws = workspaces.first(where: { $0.projects.contains { $0.id == projectId } }) else { return }
        setActiveId(ws.id)        // 대상 워크스페이스로
        setActiveProject(projectId) // 그 안의 프로젝트로 (+배지 해제)
        if let tabId, let uuid = UUID(uuidString: tabId), let store = stores[projectId] {
            store.revealTab(TabID(uuid: uuid))
        }
        showGitPanel = true       // 도구 패널(Git) 자동 오픈 — 무엇이 바뀌었는지 바로 체크
        NSApp.activate(ignoringOtherApps: true)
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
        guard !slots.isEmpty else { return }
        let cursor = cursorRank()
        // 현재 위치보다 뒤(사전식)인 첫 슬롯, 없으면 첫 슬롯으로 순환.
        let target = slots.first { cursor.lexicographicallyPrecedes($0.rank) } ?? slots[0]
        setActiveId(target.workspaceId)         // 대상 워크스페이스로
        setActiveProject(target.projectId)      // 그 안의 프로젝트로 (+배지 해제)
        stores[target.projectId]?.revealTab(target.tabId) // 그 탭 선택·포커스 (+배지 해제)
        NSApp.activate(ignoringOtherApps: true)
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeId }
    }

    /// 백그라운드 활동(●)이 있는 워크스페이스 id 집합. badgedProjects에서 파생 —
    /// 프로젝트 하나라도 배지면 그 워크스페이스가 배지(사이드바 ●). 사이드바가 관측해 그린다.
    var badgedWorkspaces: Set<String> {
        var result: Set<String> = []
        for ws in workspaces where ws.projects.contains(where: { badgedProjects.contains($0.id) }) {
            result.insert(ws.id)
        }
        return result
    }

    /// 활성 워크스페이스의 활성 프로젝트.
    var activeProject: Project? {
        activeWorkspace?.activeProject
    }

    /// 활성 워크스페이스의 활성 프로젝트 스토어(단축키 대상 — ⌘T/⌘D/⌘W/⌘F).
    var activeStore: TerminalStore? {
        guard let ws = activeWorkspace, let project = ws.activeProject else { return nil }
        return store(for: project, in: ws)
    }

    /// 프로젝트의 터미널 스토어(없으면 생성). cwd는 프로젝트 경로(없으면 워크스페이스 경로 상속).
    func store(for project: Project, in workspace: Workspace) -> TerminalStore {
        if let s = stores[project.id] { return s }
        let cwd = project.path ?? workspace.path
        let s = TerminalStore(app: app, cwd: cwd, restoreSnap: savedLayouts[project.id],
                              commandFinishedThresholdNs: config.commandFinishedThresholdNs)
        let pid = project.id
        s.onProjectActivity = { [weak self] in MainActor.assumeIsolated { self?.markProjectBadge(pid) } }
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
        stores[project.id] = s
        // 첫 store 생성(=첫 터미널이 이 경로에서 시작) 시점에 세션 기준선을 1회 기록(DESIGN 4.4 #2).
        recordSessionBaseline(projectId: project.id, cwd: cwd)
        return s
    }

    // MARK: 세션 기준선 (DESIGN 4.4 #2 — "이번 세션에 에이전트가 한 일"의 기준점)

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

    /// 프로젝트 id로 프로젝트를 찾는다(어느 워크스페이스든).
    private func project(_ projectId: String) -> Project? {
        for ws in workspaces {
            if let p = ws.projects.first(where: { $0.id == projectId }) { return p }
        }
        return nil
    }

    /// 백그라운드 프로젝트에 활동(●)이 있음을 표시. 지금 보고 있는 활성 프로젝트(=활성 워크스페이스의
    /// 활성 프로젝트)면 무시하고, 그 외(백그라운드 워크스페이스의 프로젝트 포함)는 전부 배지한다.
    /// stores는 프로젝트 id로 전역 유지되므로 백그라운드 워크스페이스 store의 활동도 여기로 들어온다.
    private func markProjectBadge(_ projectId: String) {
        guard projectId != activeProject?.id else { return }
        insertBadge(projectId)
    }

    /// 배지 추가/해제는 이 두 함수로 일원화한다 — 매번 Dock 카운트를 함께 갱신하기 위해.
    private func insertBadge(_ projectId: String) {
        badgedProjects.insert(projectId)
        updateDockBadge()
    }

    private func clearBadge(_ projectId: String) {
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

    func toggleExplorer() { showExplorer.toggle() }
    func toggleGitPanel() { showGitPanel.toggle() }
    func setExplorer(_ open: Bool) { showExplorer = open }
    func setGitPanel(_ open: Bool) { showGitPanel = open }

    // MARK: 워크스페이스 액션

    func setActiveId(_ id: String) {
        guard activeId != id else { return }
        activeId = id
        // 이 워크스페이스로 넘어와 그 활성 프로젝트를 보게 됐으니 해당 배지 해제.
        if let ws = workspaces.first(where: { $0.id == id }), let pid = ws.activeProject?.id {
            clearBadge(pid)
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
        activeId = ws.id
        save()
        return ws
    }

    func ensureInitial(path: String?) {
        guard workspaces.isEmpty else { return }
        let ws = createWorkspace(path: path)
        workspaces = [ws]
        activeId = ws.id
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

    /// 활성 워크스페이스에서 프로젝트를 앞/뒤로 순환 전환한다(⌘⇧] / ⌘⇧[).
    func cycleProject(forward: Bool) {
        guard let ws = activeWorkspace, ws.projects.count > 1,
              let idx = ws.projects.firstIndex(where: { $0.id == ws.activeProjectId }) else { return }
        let count = ws.projects.count
        let next = (idx + (forward ? 1 : count - 1)) % count
        setActiveProject(ws.projects[next].id)
    }

    /// 프로젝트를 닫는다(마지막 하나는 남긴다). 활성이면 인접 프로젝트로 전환.
    func closeProject(_ projectId: String) {
        stores[projectId] = nil
        savedLayouts[projectId] = nil
        clearBadge(projectId)
        updateActiveWorkspace { ws in
            guard ws.projects.count > 1,
                  let idx = ws.projects.firstIndex(where: { $0.id == projectId }) else { return ws }
            var next = ws
            next.projects.remove(at: idx)
            if next.activeProjectId == projectId {
                next.activeProjectId = next.projects[min(idx, next.projects.count - 1)].id
            }
            return next
        }
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

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var activeId: String
        var sidebarMode: SidebarMode
        var layouts: [String: PaneSnapshot]? // 프로젝트 id → 통합 스냅샷(터미널·문서·diff 전부).

        init(workspaces: [Workspace], activeId: String, sidebarMode: SidebarMode, layouts: [String: PaneSnapshot]?) {
            self.workspaces = workspaces; self.activeId = activeId; self.sidebarMode = sidebarMode; self.layouts = layouts
        }

        // layouts는 포맷이 바뀔 수 있어 관대하게 디코드 — 옛 포맷이면 nil로 두고 워크스페이스는 보존한다.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            workspaces = try c.decode([Workspace].self, forKey: .workspaces)
            activeId = try c.decode(String.self, forKey: .activeId)
            sidebarMode = try c.decode(SidebarMode.self, forKey: .sidebarMode)
            layouts = (try? c.decodeIfPresent([String: PaneSnapshot].self, forKey: .layouts)) ?? nil
        }
    }

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.v4.json") // 워크스페이스 보존, layouts만 통합 스냅샷으로 관대 디코드
    }()

    func save() {
        // 인스턴스화된 스토어(=열린 프로젝트)의 현재 레이아웃을 통합 스냅샷으로 반영. 빈 스토어는 스킵.
        for (projectId, store) in stores where !store.controller.allTabIds.isEmpty {
            savedLayouts[projectId] = store.snapshot()
        }
        let snapshot = Persisted(workspaces: workspaces, activeId: activeId, sidebarMode: sidebarMode,
                                 layouts: savedLayouts)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let snapshot = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        workspaces = snapshot.workspaces
        activeId = snapshot.activeId
        sidebarMode = snapshot.sidebarMode
        savedLayouts = snapshot.layouts ?? [:]
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
