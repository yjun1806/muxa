import AppKit
import SwiftUI

/// 서비스 도크 — 탐색기·Git과 같은 **우측 도킹 패널**(⌘J). 본문(터미널)을 밀어내고 좌측 경계로 너비를
/// 조절한다(`ContentView.serviceDock`이 `ResizablePanel`로 감싼다).
///
/// **[좌: 목록 | 우: 로그/터미널]** — 좌측 상단의 **탭 스위처**가 세 축을 가른다:
///  - **서비스**(끝없는 프로세스·등록·자동기동) · **스크립트**(끝있는 명령·등록·반복) ·
///    **일회용**(즉석 명령·등록 안 함·1회 — 입력창 + 최근 실행 기록).
/// 스크립트·일회용은 서비스와 **같은 tmux 백엔드**를 재사용하고, 우측 상세도 같다(실행 중 attach·종료 로그).
///
/// **목록은 창 전체다**(모든 워크스페이스·프로젝트, 활성 탭 종류로 필터). 다른 워크스페이스의 dev
/// 서버가 죽어도 여기서 바로 보이고, 클릭하면 활성 프로젝트 전환 없이 그 자리에서 로그가 뜬다.
struct ServiceDock: View {
    let state: AppState

    /// 추가 시트 — 서비스·스크립트가 같은 시트를 문구만 바꿔 쓴다(도크는 메인 창이라 `.sheet` 정상).
    @State private var showServiceAdd = false
    @State private var showScriptAdd = false
    /// 스크립트 시트 프리필(일회용 승격 시 명령을 미리 채움).
    @State private var scriptPrefill = ""
    /// 일회용 입력창 명령 + 경과 tick + 포커스 + 프로젝트 감지 제안.
    @State private var oneOffCommand = ""
    @State private var now = Date()
    @FocusState private var oneOffFocused: Bool
    /// 히스토리에서 실행 내역이 펼쳐진 명령(command). 한 번에 하나만 펼친다.
    @State private var expandedCommand: String?
    /// 현재 실행 경로(nil=프로젝트 상속). 입력창의 `cd`가 세션 내에서 옮긴다(미니 터미널 프롬프트).
    @State private var selectedCwd: String?
    /// 자동완성 드롭다운(경로·명령)에서 하이라이트한 후보 인덱스(↑↓·hover로 이동, Tab·클릭으로 완성).
    @State private var completionSelection = 0
    /// package.json·Makefile·scripts/ 에서 발견한 프로젝트 스크립트(활성 프로젝트 cwd 기준).
    @State private var discoveredScripts: [DiscoveredScript] = []

    /// 창 전체 서비스·스크립트·일회용(소속 포함).
    private var all: [LocatedService] { state.allLocatedServices }
    private var allScripts: [LocatedScript] { state.allLocatedScripts }
    private var oneOff: [LocatedScript] { state.oneOffLocatedScripts }
    private var tab: DockTab { state.dockTab }

    /// 도크가 상세로 보여줄 수 있는 것 — 서비스·스크립트·일회용(선택 id `selectedServiceId` 공유).
    private enum Selection {
        case service(LocatedService)
        case script(LocatedScript)
        case oneoff(LocatedScript)
    }

    /// **활성 탭 기준** 상세 대상 — 선택 id가 그 탭 것이면 그것, 아니면 그 탭 첫 항목(일회용은 최근).
    /// 탭이 선택을 거르므로 "다른 탭 항목을 보는 중인데 목록은 이 탭" 모순이 안 생긴다.
    private var selected: Selection? {
        switch tab {
        case .services:
            if let id = state.selectedServiceId, let s = all.first(where: { $0.id == id }) { return .service(s) }
            return all.first.map(Selection.service)
        case .commands:
            // 선택 id가 등록 스크립트면 .script, 즉석 인스턴스면 .oneoff. 기본은 최근 실행(oneOff 마지막).
            if let id = state.selectedServiceId {
                if let s = allScripts.first(where: { $0.id == id }) { return .script(s) }
                if let s = oneOff.first(where: { $0.id == id }) { return .oneoff(s) }
            }
            return oneOff.last.map(Selection.oneoff)
        }
    }

    /// 지금 선택된 항목의 id — 행 강조가 어느 종류인지 몰라도 되게 한 겹 벗긴다.
    private var selectedId: String? {
        switch selected {
        case .service(let s): return s.id
        case .script(let s): return s.id
        case .oneoff(let s): return s.id
        case .none: return nil
        }
    }

    /// 활성 탭 종류로 거른 워크스페이스 2단 스코프(서비스만 / 스크립트만). 일회용은 스코프를 안 쓴다
    /// (소수·휘발이라 워크스페이스 위계가 과하다 — 입력창 + 최근순 flat).
    private var scopes: [ServiceScope] {
        let cur = state.activeProject?.id ?? ""
        switch tab {
        case .services: return groupByWorkspace(all, scripts: [], currentWorkspaceId: state.activeId, currentProjectId: cur)
        case .commands: return [] // 명령 탭은 스코프 트리를 안 쓴다 — flat(입력창 + 등록 섹션 + 히스토리)
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.pPanel)
            .sheet(isPresented: $showServiceAdd) { serviceAddSheet }
            .sheet(isPresented: $showScriptAdd) { scriptAddSheet }
            // 추가·승격 요청은 원샷(도크가 소비하고 내린다). ⌘K·일회용 승격이 여기로 온다.
            .onChange(of: state.serviceAddRequested, initial: true) { _, req in
                guard req else { return }
                state.serviceAddRequested = false
                showServiceAdd = true
            }
            .onChange(of: state.scriptAddRequested, initial: true) { _, req in
                guard req else { return }
                state.scriptAddRequested = false
                scriptPrefill = state.scriptAddPrefillCommand ?? ""
                state.scriptAddPrefillCommand = nil
                showScriptAdd = true
            }
            .onChange(of: state.oneOffFocusRequested, initial: true) { _, req in
                guard req else { return }
                state.oneOffFocusRequested = false
                oneOffFocused = true
            }
            // 등록 해제 실행취소 스낵바 — 도크 바닥에 잠깐 뜬다.
            .overlay(alignment: .bottom) {
                if let pd = state.pendingDeletion {
                    UndoSnackbar(label: pd.label,
                                 undo: { state.undoDeletion() },
                                 dismiss: { state.dismissUndo() })
                        .padding(.horizontal, Space.md)
                        .padding(.bottom, Space.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.medium, value: state.pendingDeletion?.id)
            // Esc로 도크를 닫는다(터미널이 포커스면 그쪽이 먼저 먹는다 — 목록·상세에서만).
            .onExitCommand { state.closeServiceDock() }
    }

    @ViewBuilder
    private var content: some View {
        // **탭 바는 도크 전폭**이다 — [목록|상세] 위를 가로지른다. 탭이 목록 열에 갇히면 닫기가 도크
        // 한가운데 놓이고 "두 패널"처럼 보인다. 탭은 도크 전체를 지배하므로 상단 전폭이 맞다.
        VStack(spacing: 0) {
            dockTopBar
            HDivider()
            if !state.servicesAvailable {
                // tmux 미설치는 두 축 공통 엔진의 부재 — 탭 줄은 보이되 아래는 설치 안내로 채운다.
                setup
            } else {
                VStack(spacing: 0) {
                    // 명령 탭: 프롬프트를 **도크 전폭**으로 올린다(좁은 목록 열에 갇히면 라인이 답답하다).
                    // 그 아래에 [명령 목록 | 터미널/로그]이 좌우로 나뉜다.
                    if tab == .commands {
                        // zIndex — 자동완성 팝업이 오버레이로 아래 분할 위에 떠야 한다(뒤 형제가 덮지 않게).
                        inputArea.padding(.vertical, Space.sm).zIndex(1)
                        HDivider()
                    }
                    // 터미널을 접으면 목록이 도크 전체를 채운다(도크 폭은 바깥 ResizablePanel이 목록 폭으로 줄인다).
                    if state.dockCollapsed {
                        listBody
                    } else {
                        HStack(spacing: 0) {
                            ResizableLeftColumn(width: state.serviceListWidth,
                                                range: AppState.serviceListWidthRange) { w in
                                state.setServiceListWidth(w)
                            } content: {
                                listBody
                            }
                            detailColumn
                        }
                    }
                }
            }
        }
    }

    /// 도크 상단 **전폭** 바 — [탭 스위처] ····· [✕(⌘J)]. **추가·비우기는 여기 두지 않는다**(＋가 탭 옆이면
    /// "탭 추가"로 오독). 추가는 현재 워크스페이스 카드 안, 일회용 비우기는 그 탭 목록 헤더가 맡는다.
    private var dockTopBar: some View {
        HStack(spacing: Space.sm) {
            tabSwitcher
            Spacer(minLength: Space.xs)
            // 명령 탭에서만 — 터미널(상세 열)을 접어 도크를 목록 폭으로 좁힌다. 펼치면 [목록|터미널]로 돌아온다.
            if tab == .commands {
                IconButton(icon: "sidebar.right",
                           help: state.commandTerminalCollapsed ? "터미널 펴기 — 출력을 옆에 표시"
                                                                : "터미널 접기 — 도크를 좁게") {
                    state.toggleCommandTerminalCollapsed()
                }
            }
            IconButton(icon: "xmark", help: "도크 닫기 (⌘J) — 프로세스는 계속 돕니다") {
                state.closeServiceDock()
            }
        }
        .panelBar(height: RowHeight.panelHeader)
    }

    // MARK: 좌 — (탭별) 목록 본문. 탭 바는 위 전폭이라 여기엔 없다.

    @ViewBuilder
    private var listBody: some View {
        Group {
            switch tab {
            case .services: scopeList
            case .commands: commandsColumn
            }
        }
        // 높이를 채워 상단 정렬 — 안 하면 내용이 짧을 때(일회용 빈 상태) HStack이 열을 세로 중앙에 놓는다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 탭 스위처 — 좁으면(목록 열 하한 150) 라벨을 접어 **글리프만** 남긴다(잘린 "스크립…"을 만들지 않는다).
    private var tabSwitcher: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(labeled: true)
            tabRow(labeled: false)
        }
    }

    private func tabRow(labeled: Bool) -> some View {
        HStack(spacing: Space.tight) {
            ForEach(DockTab.allCases) { tabPill($0, labeled: labeled) }
        }
    }

    /// 탭 한 개 — FooterChip 알약과 같은 색규칙(선택=`pBtnActive` 눌린 상태 유지). 글리프는 **카테고리
    /// 마커**(상태색 아님)라 텍스트색을 따른다. 실패가 있을 때만 빨간 롤업 점(개수 배지는 없다).
    private func tabPill(_ t: DockTab, labeled: Bool) -> some View {
        let sel = tab == t
        return Button { state.dockTab = t } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: t.icon).font(.muxa(.label))
                if labeled {
                    Text(t.title).font(.muxa(.label, weight: sel ? .semibold : .regular))
                }
                if tabHasFailure(t) {
                    Circle().fill(Color.pServiceExited)
                        .frame(width: IconSize.dotSmall, height: IconSize.dotSmall)
                }
            }
            .foregroundStyle(sel ? Color.pFg : Color.pMuted)
            .padding(.horizontal, Space.xs)
            .frame(height: RowHeight.tight)
            .background(Color.footerChip(isOpen: sel, hovered: false), in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(t.title)
        .accessibilityLabel("\(t.title) 탭\(sel ? ", 선택됨" : "")\(tabHasFailure(t) ? ", 실패 있음" : "")")
    }

    /// 그 탭 종류에 **창 전체** 기준 실패가 하나라도 있나 — 다른 탭을 보는 중에도 건너갈 신호를 준다.
    private func tabHasFailure(_ t: DockTab) -> Bool {
        switch t {
        case .services: return all.contains { state.serviceMonitor.state(of: $0.id).isFailure }
        case .commands: return allScripts.contains { state.scriptRuns[$0.id]?.isFailure == true }
            || oneOff.contains { state.scriptRuns[$0.id]?.isFailure == true }
        }
    }

    // MARK: 좌 — 서비스·스크립트 탭의 스코프 목록

    private var scopeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.groupGap) {
                // 현재 워크스페이스는 **비어도 항상** 그린다 — 그 카드가 "여기에 추가"의 진입점을 품는다.
                currentScope(currentWorkspaceScope)
                ForEach(otherScopes) { otherScope($0) }
            }
            .padding(.vertical, Space.xs)
        }
    }

    /// 현재 워크스페이스 스코프 — 목록에 있으면 그것, 없으면(항목 0) 빈 스코프로 만들어 추가 행만 품게 한다.
    private var currentWorkspaceScope: ServiceScope {
        if let s = scopes.first(where: { $0.isCurrent }) { return s }
        return ServiceScope(workspaceId: state.activeId,
                            workspaceName: state.activeWorkspace?.name ?? "",
                            isCurrent: true, groups: [])
    }
    private var otherScopes: [ServiceScope] { scopes.filter { !$0.isCurrent } }

    /// 현재 워크스페이스 — pBg 콘텐츠 카드로 "여기/내 것" 영역을 만든다(명도·경계, 색맹 안전). 늘 펼침.
    /// 카드 **안**에 추가 행을 둔다 — 도크가 창 전체를 담아도 "추가는 여기(활성 프로젝트)"가 위치로 분명하다.
    @ViewBuilder
    private func currentScope(_ scope: ServiceScope) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            scopeHeader(scope, chevron: nil, collapsed: false)
            scopeItems(scope)
            if scope.groups.isEmpty {
                Text("등록된 서비스가 없습니다.") // scopeList는 서비스 탭 전용(명령은 commandsColumn)
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .padding(.horizontal, Space.sm).padding(.top, Space.tight)
            }
            if state.activeProject != nil {
                AddInCardRow(kind: .services, projectName: state.activeProject?.name ?? "") {
                    showServiceAdd = true
                }
            }
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, Space.sm)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.pBg)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        }
        .padding(.horizontal, Space.xs)
    }

    /// 다른 워크스페이스 — 기본 접힘(한 줄: chevron·개수·롤업 상태). 펼치면 카드 없이 목록을 편다.
    @ViewBuilder
    private func otherScope(_ scope: ServiceScope) -> some View {
        let expanded = state.expandedServiceScopes.contains(scope.id)
        VStack(alignment: .leading, spacing: Space.tight) {
            Button { state.toggleServiceScope(scope.id) } label: {
                scopeHeader(scope, chevron: expanded ? "chevron.down" : "chevron.right", collapsed: !expanded)
            }
            .buttonStyle(.plain)
            .clickCursor()
            if expanded { scopeItems(scope) }
        }
        .padding(.horizontal, Space.xs)
    }

    /// 스코프 머리글 — (옵션 chevron) · 레이어 글리프 · 대문자 이름 · (접혔으면 롤업 글리프+개수).
    private func scopeHeader(_ scope: ServiceScope, chevron: String?, collapsed: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if let chevron {
                Image(systemName: chevron).font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted).frame(width: IconSize.statusSlot)
            }
            Image(systemName: scope.isCurrent ? "square.stack.fill" : "square.stack")
                .font(.muxa(.micro))
                .foregroundStyle(scope.isCurrent ? Color.pFg : Color.pMuted)
            Text(scope.workspaceName)
                .font(.muxaLabel).tracking(Tracking.label).textCase(.uppercase)
                .foregroundStyle(scope.isCurrent ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            if collapsed {
                let st = rollup(scope)
                Image(systemName: ServiceStatusStyle.glyph(st))
                    .font(.muxa(.micro)).foregroundStyle(ServiceStatusStyle.color(st))
                Text("\(scope.serviceCount)")
                    .font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(minHeight: RowHeight.tight)
        .contentShape(Rectangle())
    }

    /// 스코프의 프로젝트 그룹 + 행. 탭이 종류를 이미 갈랐으므로 한 그룹엔 한 종류만 있다 —
    /// 섹션 소제목 없이 그 종류의 행만 편다(둘 중 하나는 비어 아무것도 안 그린다).
    @ViewBuilder
    private func scopeItems(_ scope: ServiceScope) -> some View {
        ForEach(scope.groups) { group in
            // 프로젝트가 여럿일 때만 프로젝트 소제목 — 하나면 헤더 아래 바로 행(중복 방지).
            if scope.groups.count > 1 {
                Text(group.title)
                    .font(.muxa(.caption, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                    .padding(.horizontal, Space.sm)
                    .padding(.top, Space.tight)
            }
            ForEach(group.services) { item in row(item) }
            ForEach(group.scripts) { item in scriptRow(item) }
        }
    }

    /// 접힌 스코프의 롤업 상태 — 죽은 게 하나라도 있으면 그게 이긴다(칩 요약과 같은 규칙).
    /// 스코프가 이미 탭 종류로 필터돼 있어 그 종류만 집계된다(스크립트 탭 롤업에 서비스 죽음이 안 섞인다).
    private func rollup(_ scope: ServiceScope) -> ServiceState {
        var states = scope.allServices.map { state.serviceMonitor.state(of: $0.service.id) }
        for script in scope.allScripts {
            guard let run = state.scriptRuns[script.id] else { continue }
            switch run.state {
            case .running: states.append(.running)
            case .finished(let code, _):
                if let code, code != 0 { states.append(.exited(code: code)) }
            }
        }
        return ServiceStatusStyle.summarize(states)
    }

    /// 서비스 행 — 클릭=상세 선택, hover=중단/시작(비파괴). 삭제는 상세 헤더에만.
    private func row(_ item: LocatedService) -> some View {
        let st = state.serviceMonitor.state(of: item.service.id)
        return ServiceRow(service: item.service,
                          status: st,
                          port: state.serviceMonitor.ports[item.service.id],
                          selected: selectedId == item.service.id,
                          stopped: state.userStoppedServiceIds.contains(item.service.id),
                          action: { state.selectedServiceId = item.service.id },
                          onToggleRun: {
                              if st == .running { state.stopService(item.service.id, in: item.projectId) }
                              else if let cwd = item.cwd { state.restartService(item.service.id, in: item.projectId, cwd: cwd) }
                          })
    }

    /// 스크립트 행 — 클릭=상세 선택, hover ▶=백그라운드 실행.
    private func scriptRow(_ item: LocatedScript) -> some View {
        ScriptDockRow(script: item.script, run: state.scriptRuns[item.id],
                      selected: selectedId == item.id,
                      action: { state.selectedServiceId = item.id },
                      onRun: { state.runScript(item.script, in: item.projectId) })
    }

    // MARK: 좌 — 일회용 탭 (입력창 + 최근 실행 기록)

    /// 명령 섹션(즐겨찾기·프로젝트 스크립트·히스토리) — 목록 렌더와 명령 완성이 함께 쓴다.
    private var sections: (favorites: [CommandEntry], projectScripts: [DiscoveredScript], history: [CommandEntry]) {
        CommandStore.panelSections(state.commandEntries(of: projId), discovered: discoveredScripts)
    }

    /// 스크립트를 발견·실행할 폴더 — 프롬프트에서 `cd`로 옮긴 곳(`selectedCwd`), 없으면 프로젝트 루트.
    /// 프롬프트 표시(`promptPath`)와 달리 홈 폴백을 두지 않는다 — 프로젝트가 없으면 발견도 없다(빈 목록).
    /// 발견과 실행이 **같은 경로**를 봐야 "목록에 뜬 스크립트 = 실제 실행되는 스크립트"가 어긋나지 않는다.
    private var scriptCwd: String? { selectedCwd ?? state.activeProjectCwd }

    private var commandsColumn: some View {
        // 프롬프트(inputArea)는 이제 도크 전폭(content)에 있다 — 여기는 목록만.
        // flat 섹션 하나의 스크롤 — 자주 쓰는 순서(즐겨찾기 → 최근 실행 → 프로젝트 스크립트 카탈로그).
        let s = sections
        return ScrollView {
            // 섹션 사이는 넓게(xl) — 그룹 안 1pt와 대비를 벌려야 헤더가 "머리글"로 읽힌다.
            VStack(alignment: .leading, spacing: Space.xl) {
                favoritesFlat(s.favorites)
                if !s.history.isEmpty { historyFlat(s.history) }
                if !s.projectScripts.isEmpty { projectScriptsFlat(s.projectScripts) }
            }
            .padding(.vertical, Space.md)
        }
        .tick(every: 1, into: $now)
        .task(id: scriptCwd) {
            let found = ProjectScripts.discover(in: scriptCwd)
            discoveredScripts = found.scripts.map {
                DiscoveredScript(name: $0.name,
                                 command: ProjectScripts.command(for: $0, manager: found.manager ?? .npm),
                                 source: $0.source.rawValue)
            }
        }
    }

    /// 입력 영역 — **2줄 터미널 프롬프트.** 위: 현재 실행 경로(또렷하게). 아래: `❯` 명령 입력.
    /// `cd <경로>`는 실행 경로를 옮기고(실행 안 함), 그 외는 그 경로에서 실행한다. Enter 하나로 끝.
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // 경로 줄 — 이동해도 지금 어디인지 바로 보이게. 길면 앞을 잘라 현재 폴더가 끝에 남는다.
            HStack(spacing: Space.tight) {
                Image(systemName: "folder").font(.muxa(.nano)).foregroundStyle(Color.pBrand)
                Text(promptPath).font(.muxaMono(.caption)).foregroundStyle(Color.pFg.opacity(0.75))
                    .lineLimit(1).truncationMode(.head)
            }
            .padding(.horizontal, Space.sm)

            inputRow
        }
        .padding(.horizontal, Space.sm)
    }

    /// 프롬프트 입력 줄 — `❯` 명령. 자동완성 드롭다운은 이 줄 바로 아래에 뜬다.
    private var inputRow: some View {
        HStack(spacing: Space.xs) {
            Text("❯").font(.muxaMono(.body)).foregroundStyle(Color.pBrand)
            TextField("명령 — cd 로 이동, 그 외 실행", text: $oneOffCommand)
                .textFieldStyle(.plain).font(.muxaMono(.body)).foregroundStyle(Color.pFg)
                .focused($oneOffFocused).onSubmit(handleInput)
                .accessibilityLabel("명령 입력")
        }
        .padding(.horizontal, Space.sm).frame(height: RowHeight.toolbar)
        .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        // 입력이 바뀌면 하이라이트를 맨 위로 되돌린다(엉뚱한 줄이 선택된 채 남지 않게).
        .onChange(of: oneOffCommand) { completionSelection = 0 }
        // 키보드 탐색 — 필드가 포커스라 여기 붙여 받는다(↑↓ 이동, Tab 완성). Enter는 onSubmit이 실행.
        .onKeyPress(.upArrow) { moveCompletion(-1) }
        .onKeyPress(.downArrow) { moveCompletion(1) }
        .onKeyPress(.tab) { acceptCompletion() }
        // 자동완성 드롭다운 — 입력 줄 아래에 떠서(오버레이) 아래 분할을 가린다. 터미널식 세로 목록.
        // `cd `면 경로 폴더, 그 외 입력이면 명령 이름(즐겨찾기·발견 스크립트·히스토리)을 완성한다.
        .overlay(alignment: .topLeading) {
            if let items = completionItems {
                CompletionPopup(items: items, typeLabel: completionTypeLabel,
                                selection: min(completionSelection, items.count - 1),
                                onPick: { acceptCompletion(at: $0) },
                                onHover: { completionSelection = $0 })
                    .fixedSize()
                    .offset(y: RowHeight.toolbar + Space.xs)
            }
        }
    }

    // MARK: 자동완성 — 경로(cd)와 명령 이름을 한 축의 selection·키보드로 다룬다(둘은 배타적).

    /// cd 경로 후보 — 입력이 `cd <부분>`이면 그 경로의 하위 폴더(아니면 nil).
    private var pathCompletions: [String]? {
        guard oneOffCommand.hasPrefix("cd ") else { return nil }
        let arg = String(oneOffCommand.dropFirst(3))
        let base = selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory())
        let (dir, prefix) = PathComplete.split(arg, base: base)
        return PathComplete.directories(in: dir, prefix: prefix)
    }

    /// 명령 이름 후보 — `cd ` 모드가 아니고 입력이 muxa가 아는 명령에 걸리면(아니면 nil).
    private var commandCompletions: [CommandSuggestion]? {
        guard !oneOffCommand.hasPrefix("cd ") else { return nil }
        let s = sections
        let all = CommandComplete.candidates(favorites: s.favorites, scripts: discoveredScripts,
                                             history: s.history)
        let matched = CommandComplete.match(oneOffCommand, in: all)
        return matched.isEmpty ? nil : matched
    }

    /// 드롭다운에 그릴 행 — 경로면 폴더, 명령이면 이름+소스 부제(둘 중 활성 하나).
    private var completionItems: [CompletionPopup.Item]? {
        if let names = pathCompletions, !names.isEmpty {
            return names.map { .init(glyph: "folder.fill", brandGlyph: true, title: $0 + "/", subtitle: nil) }
        }
        if let cmds = commandCompletions {
            return cmds.map { .init(glyph: $0.glyph, brandGlyph: false, title: $0.label, subtitle: $0.source) }
        }
        return nil
    }
    private var completionTypeLabel: String { pathCompletions != nil ? "folder" : "command" }
    private var completionCount: Int { pathCompletions?.count ?? commandCompletions?.count ?? 0 }

    /// ↑↓ 하이라이트 이동(순환). 후보가 없으면 키를 흘려보낸다(.ignored).
    private func moveCompletion(_ step: Int) -> KeyPress.Result {
        let n = completionCount
        guard n > 0 else { return .ignored }
        completionSelection = ((completionSelection + step) % n + n) % n
        return .handled
    }

    /// Tab — 하이라이트한 후보로 완성한다(포커스 이동을 막으려 .handled). 후보 없으면 흘려보낸다.
    private func acceptCompletion() -> KeyPress.Result {
        guard completionCount > 0 else { return .ignored }
        acceptCompletion(at: min(completionSelection, completionCount - 1))
        return .handled
    }

    /// 후보 하나를 입력창에 채운다 — 경로면 그 폴더로(끝에 `/`, 계속 탐색), 명령이면 명령 전체(수정·실행은 이어서).
    private func acceptCompletion(at index: Int) {
        if let names = pathCompletions, index < names.count {
            let base = selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory())
            let arg = String(oneOffCommand.dropFirst(3))
            let (dir, _) = PathComplete.split(arg, base: base)
            oneOffCommand = "cd " + PathComplete.display((dir as NSString).appendingPathComponent(names[index])) + "/"
        } else if let cmds = commandCompletions, index < cmds.count {
            oneOffCommand = cmds[index].command
        }
        oneOffFocused = true
    }

    /// 프롬프트에 표시할 현재 실행 경로 — 홈은 `~`, 좁은 폭이라 앞을 자른다(끝 폴더가 보이게).
    private var promptPath: String {
        PathComplete.display(selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory()))
    }

    /// 타이핑한 `cd` 인자가 그 자체로 존재하는 폴더인가(`cd ..`·`cd macos`·`cd macos/`).
    /// 맞으면 Enter는 하이라이트가 아니라 타이핑한 경로로 이동한다(기존 동작 보존).
    private var typedPathIsExistingDir: Bool {
        guard oneOffCommand.hasPrefix("cd ") else { return false }
        let arg = String(oneOffCommand.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard !arg.isEmpty else { return false }
        let base = selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory())
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: PathComplete.expand(arg, base: base), isDirectory: &isDir)
            && isDir.boolValue
    }

    /// 입력 처리(Enter) — `cd <경로>`면 실행 경로를 옮기고, 그 외는 그 경로에서 실행한다.
    private func handleInput() {
        // 폴더 드롭다운이 떠 있고 **타이핑한 경로 자체로는 갈 수 없을 때**(빈 `cd ` 나 접두사 `cd mac`),
        // Enter는 하이라이트한 폴더로 이동한다 — 목록에서 골라 Enter가 그 폴더로 가는 자연스러운 기대.
        // (`cd ..`·`cd macos`처럼 타이핑 경로가 그대로 존재하면 아래 일반 처리가 그리로 보낸다. Tab은 채우기만.)
        if let names = pathCompletions, !names.isEmpty, !typedPathIsExistingDir {
            let base = selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory())
            let (dir, _) = PathComplete.split(String(oneOffCommand.dropFirst(3)), base: base)
            let target = (dir as NSString).appendingPathComponent(names[min(completionSelection, names.count - 1)])
            selectedCwd = (target == state.activeProjectCwd) ? nil : target
            oneOffCommand = ""
            return
        }
        let trimmed = oneOffCommand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let base = selectedCwd ?? (state.activeProjectCwd ?? NSHomeDirectory())
        if trimmed == "cd" || trimmed == "cd ~" {
            selectedCwd = nil // 프로젝트 루트로
            oneOffCommand = ""
            return
        }
        if trimmed.hasPrefix("cd ") {
            let arg = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let path = PathComplete.expand(arg, base: base)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                selectedCwd = (path == state.activeProjectCwd) ? nil : path
            } else {
                state.attention.recordSystem(title: "cd: \(arg) — 그런 폴더가 없습니다")
            }
            oneOffCommand = ""
            return
        }
        state.runCommand(trimmed, cwd: selectedCwd, in: projId)
        oneOffCommand = ""
    }

    /// flat 섹션 — 소섹션 머리글 + 행. **카드·선 없이** 여백으로 구분한다(집값 철학: 위계는 간격이 만든다).
    /// 리듬의 핵심은 **대비**다 — 그룹 안 행은 촘촘히(1pt), 헤더→행은 조금(xs), 섹션 사이는 넓게(호출부 xl).
    /// 헤더는 크롬 공용 머리글 폰트(`muxaLabel`)를 써 사이드바 섹션과 한 언어로 읽힌다.
    @ViewBuilder
    private func flatSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.muxaLabel).tracking(Tracking.label)
                .textCase(.uppercase).foregroundStyle(Color.pMuted).padding(.horizontal, Space.sm)
            VStack(alignment: .leading, spacing: 1) { content() }
        }
    }

    /// 즐겨찾기 — 자주 쓰는 것. 비어도 헤더는 그린다(F3), 비면 상태별 안내(F1).
    @ViewBuilder
    private func favoritesFlat(_ items: [CommandEntry]) -> some View {
        flatSection("즐겨찾기") {
            if items.isEmpty {
                Text(favoritesEmptyCopy).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.sm)
            } else {
                ForEach(items) { entry in
                    CommandFavoriteRow(entry: entry, now: now, run: runFor(entry),
                        selected: selectedId != nil && selectedId == entry.executions.first?.id,
                        onSelect: { if let id = entry.executions.first?.id { state.selectedServiceId = id } },
                        onRun: { state.runCommand(entry.command, cwd: entry.cwd, in: projId) },
                        onUnfavorite: { state.toggleCommandFavorite(entry.command, in: projId) })
                }
            }
        }
    }

    /// 최근 실행 — 명령당 한 줄, 클릭하면 실행 내역 펼침.
    @ViewBuilder
    private func historyFlat(_ items: [CommandEntry]) -> some View {
        flatSection("최근 실행") {
            ForEach(items) { entry in
                CommandHistoryRowV2(entry: entry, now: now, run: runFor(entry),
                    expanded: expandedCommand == entry.command, selectedExec: selectedId,
                    onToggle: { expandedCommand = (expandedCommand == entry.command) ? nil : entry.command },
                    onRun: { state.runCommand(entry.command, cwd: entry.cwd, in: projId) },
                    onFavorite: { state.toggleCommandFavorite(entry.command, in: projId) },
                    onDelete: { state.removeCommand(entry.command, in: projId) },
                    onSelectExec: { state.selectedServiceId = $0 })
            }
        }
    }

    /// 프로젝트 스크립트 — package.json/Makefile 발견 카탈로그(요구 1). 많으니 자주 쓰는 것 아래에 둔다.
    @ViewBuilder
    private func projectScriptsFlat(_ items: [DiscoveredScript]) -> some View {
        flatSection("프로젝트 스크립트") {
            ForEach(items) { script in
                CommandScriptRow(script: script, run: runFor(command: script.command),
                    onRun: { state.runCommand(script.command, cwd: selectedCwd, in: projId) },
                    onFavorite: { state.toggleCommandFavorite(script.command, name: script.name, cwd: selectedCwd, in: projId) })
            }
        }
    }

    private var projId: String { state.activeProject?.id ?? "" }

    /// 명령(엔트리)의 현재 실행 상태 — 최근 실행(execId)이 도는 중인지(scriptRuns가 진실).
    private func runFor(_ entry: CommandEntry) -> ScriptRun? {
        guard let execId = entry.executions.first?.id else { return nil }
        return state.scriptRuns[execId]
    }

    /// command로 실행 상태 조회(발견 스크립트 행용) — 그 명령의 엔트리가 있으면 최근 실행 상태.
    private func runFor(command: String) -> ScriptRun? {
        guard let entry = state.commandEntries(of: projId).first(where: { $0.command == command }) else { return nil }
        return runFor(entry)
    }

    /// 즐겨찾기 빈 상태 카피 — 실행 기록·발견 스크립트가 있으면 짧은 유도, 완전 첫 진입이면 온보딩.
    private var favoritesEmptyCopy: String {
        let hasHistory = state.commandEntries(of: projId).contains { !$0.favorite }
        if hasHistory || !discoveredScripts.isEmpty {
            return "실행 기록·스크립트에서 ☆를 누르면 여기 고정됩니다"
        }
        return "위에 명령을 적고 실행하면 백그라운드에서 돌고, 출력·종료 로그가 여기 남습니다. 자주 쓰는 건 ☆로 고정하세요."
    }


    // MARK: 우 — 상세 (선택 종류별)

    @ViewBuilder
    private var detailColumn: some View {
        switch selected {
        case .service(let s): detail(s)
        case .script(let s): scriptDetail(s, oneOff: false)
        case .oneoff(let s): scriptDetail(s, oneOff: true) // 같은 상세(attach·로그), 헤더 액션만 일회용 축
        case .none:
            // 실행 인스턴스가 없는 execId(과거 실행)를 골랐으면 저장된 로그를 보여준다.
            if let id = state.selectedServiceId, let log = state.commandLog(id) {
                savedLogDetail(log)
            } else {
                ZStack {
                    Color.pBg
                    Text(tab == .commands ? "명령을 실행하거나 실행 내역을 클릭하면 출력이 보입니다"
                                          : "왼쪽에서 항목을 선택하면 로그가 보입니다")
                        .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 과거 실행의 저장된 로그 — 읽기 전용(세션이 사라져 attach할 pane이 없다).
    private func savedLogDetail(_ log: String) -> some View {
        ScrollView {
            Text(log)
                .font(.muxaMono(.caption)).foregroundStyle(Color.pFg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }

    @ViewBuilder
    private func detail(_ item: LocatedService) -> some View {
        let st = state.serviceMonitor.state(of: item.service.id)
        let stopped = state.userStoppedServiceIds.contains(item.service.id)
        // **사용자 중단**만 텍스트 스냅샷이다 — 세션을 kill해 붙을 pane이 없다. 나머지(실행 중·비정상 종료·
        // 실행 전)는 attach: 비정상 종료도 remain-on-exit로 마지막 화면이 색·서식 그대로 얼어붙어 있어,
        // 텍스트로 다시 그리는 것보다 그 pane을 그대로 보는 게 충실하다(스크립트 상세와 같은 판단).
        let userStopped = stopped && st == .missing
        VStack(spacing: 0) {
            header(item)
            if userStopped {
                ServiceLogView(session: ServiceSession.name(projectId: item.projectId,
                                                            serviceId: item.service.id),
                               // finalLogs 도착 시 다시 읽도록 토큰에 존재 여부를 실어 준다.
                               reloadToken: "\(item.service.id)|\(state.serviceRestartSeq)|\(state.finalLogs[item.service.id] != nil)",
                               fallback: state.finalLogs[item.service.id],
                               onCapture: { state.recordFinalLog(item.service.id, $0) })
            } else {
                TerminalRepresentable(
                    term: state.dockTerm(serviceId: item.service.id, projectId: item.projectId, cwd: item.cwd),
                    onFocus: {}
                )
                .id(item.service.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 상세 헤더 — 상태 글리프 · 이름 · 포트/코드 꼬리표 · 명령 · (상태별)중단/시작/재실행 · 등록 해제(2단계).
    private func header(_ item: LocatedService) -> some View {
        let service = item.service
        let st = state.serviceMonitor.state(of: service.id)
        let port = state.serviceMonitor.ports[service.id]
        let stopped = state.userStoppedServiceIds.contains(service.id)
        let running = st == .running
        let notStarted: Bool = { if case .missing = st { return true }; return false }()
        return HStack(spacing: Space.sm) {
            Image(systemName: ServiceDisplay.glyph(st, stopped: stopped))
                .font(.muxa(.micro))
                .foregroundStyle(ServiceDisplay.color(st, stopped: stopped))
                .frame(width: IconSize.statusSlot)
            Text(service.name)
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .fixedSize()
            if let tail = ServiceDisplay.tail(st, port: port, stopped: stopped) {
                Text(tail).font(.muxaMono(.caption)).foregroundStyle(ServiceDisplay.color(st, stopped: stopped))
            }
            Text(service.command)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: Space.sm)
            // 단일 토글 원칙: 실행 중=[중단][재실행] / 중단됨·실행 전=[시작] / 비정상 종료=[재시작].
            if running {
                IconButton(icon: "stop.circle", help: "중단 — 프로세스만 종료, 등록은 유지") {
                    state.stopService(service.id, in: item.projectId)
                }
                IconButton(icon: "arrow.clockwise", help: "재실행") {
                    guard let cwd = item.cwd else { return }
                    state.restartService(service.id, in: item.projectId, cwd: cwd)
                }
            } else {
                IconButton(icon: (stopped || notStarted) ? "play.fill" : "arrow.clockwise",
                           help: (stopped || notStarted) ? "시작" : "재시작") {
                    guard let cwd = item.cwd else { return }
                    state.restartService(service.id, in: item.projectId, cwd: cwd)
                }
            }
            DeleteConfirmButton(help: "등록 해제",
                                prompt: running ? "실행 중인 \(service.name)을 종료하고 등록·로그를 지웁니다."
                                                : "\(service.name)의 등록과 로그를 지웁니다.",
                                confirmLabel: "등록 해제") {
                state.removeService(service.id, from: item.projectId)
            }
        }
        .panelBar(height: RowHeight.panelHeader)
        .background(Color.pPanel)
    }

    // MARK: 우 — 스크립트·일회용 상세 (실행 중 attach / 종료 로그 / 실행 전 안내)

    @ViewBuilder
    private func scriptDetail(_ item: LocatedScript, oneOff: Bool) -> some View {
        let run = state.scriptRuns[item.id]
        VStack(spacing: 0) {
            ScriptDetailHeader(state: state, item: item, run: run, oneOff: oneOff)
            if run != nil {
                // 실행 중·종료 **둘 다 attach**. remain-on-exit로 종료된 pane도 마지막 화면이 **색·서식 그대로**
                // 얼어붙어 있고, 붙으면 현재 도크 폭으로 reflow돼 좁은 폭 줄바꿈 아티팩트가 없다. 텍스트로
                // 다시 그리면(capture) 색이 죽고 폭이 어긋난다. 뷰를 안 갈아끼워(같은 서피스) 종료 순간
                // 빈 화면 레이스도 없다. 죽은 pane이라 입력은 무의미(읽기 전용과 같다). 세션이 사라졌으면
                // execCommand의 `exec -l $SHELL` 폴백이 셸을 남긴다(그 자리서 다시 돌릴 수 있게).
                TerminalRepresentable(
                    term: state.dockScriptTerm(scriptId: item.id, projectId: item.projectId, cwd: item.cwd),
                    onFocus: {}
                )
                .id("\(item.id)|\(state.serviceRestartSeq)")
            } else {
                EmptyState(icon: ScriptStatusStyle.icon,
                           title: "아직 실행한 적이 없습니다",
                           subtitle: "실행하면 백그라운드에서 돌고, 출력·종료 로그를 여기서 봅니다.") {
                    Button("실행") { state.runScript(item.script, in: item.projectId) }
                        .font(.muxa(.label))
                }
                .background(Color.pBg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 미설치 상태 (탭 아래 콘텐츠를 설치 안내로 채운다)

    private var setup: some View {
        ServiceSetupView(state: state) { command in
            state.mainStore?.injectToTerminal(command) ?? false
        }
    }

    // MARK: 추가 시트 (서비스·스크립트 — 같은 시트, 문구만 다르다)

    private var serviceAddSheet: some View {
        ServiceAddSheet(cwd: state.activeProjectCwd) { name, command, cwd in
            guard let pid = state.activeProject?.id else { return }
            state.addService(name: name, command: command, to: pid, cwd: cwd)
        }
    }

    private var scriptAddSheet: some View {
        ServiceAddSheet(
            cwd: state.activeProjectCwd,
            title: "스크립트 추가",
            footnote: "실행 경로에서 로그인 셸로 1회, 백그라운드에서 실행됩니다(탭이 뜨지 않습니다). 출력과 종료 로그는 이 도크의 스크립트 탭에서 봅니다.\n명령은 평문으로 저장됩니다 — 토큰·API 키는 명령에 적지 말고 .env에 두세요.",
            initialCommand: scriptPrefill
        ) { name, command, cwd in
            guard let projectId = state.activeProject?.id else { return }
            state.addScript(name: name, command: command, to: projectId, cwd: cwd)
        }
    }
}

/// 등록 해제 실행취소 스낵바 — 도크 바닥에 잠깐 뜨는 판. 2단계 확인이 실수를 막고, 이게 회복을 준다.
private struct UndoSnackbar: View {
    let label: String
    let undo: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: Space.md) {
            Text("\(label) 등록 해제됨").font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1)
            Spacer(minLength: Space.sm)
            Button(action: undo) {
                Text("실행 취소").font(.muxa(.label, weight: .semibold)).foregroundStyle(Color.pBrand)
            }
            .buttonStyle(.plain).clickCursor()
            IconButton(icon: "xmark", help: "닫기", action: dismiss)
        }
        .padding(.leading, Space.md).padding(.trailing, Space.xs)
        .frame(height: RowHeight.toolbar)
        .background(Color.pPanel, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .frame(maxWidth: 360)
    }
}

/// 현재 워크스페이스 카드 안의 "추가" 행 — **활성 프로젝트에 등록**한다. 대상 프로젝트를 오른쪽에
/// 명시(→ 이름)해, 도크가 창 전체(여러 워크스페이스) 목록이어도 "어디에 추가되나"가 위치·라벨로 분명하다.
private struct AddInCardRow: View {
    let kind: DockTab
    let projectName: String
    let action: () -> Void
    @State private var hovered = false

    private var label: String { kind == .commands ? "명령 추가" : "서비스 추가" }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted).frame(width: IconSize.statusSlot)
                Text(label).font(.muxa(.label)).foregroundStyle(hovered ? Color.pFg : Color.pMuted)
                Spacer(minLength: Space.sm)
                Text("→ \(projectName)")
                    .font(.muxaMono(.caption)).foregroundStyle(Color.pMuted).lineLimit(1)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(minHeight: RowHeight.row)
            .background(hovered ? Color.pBtnHover : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help("활성 프로젝트 \(projectName)에 \(label)")
        .accessibilityLabel("\(projectName)에 \(label)")
    }
}

/// 스크립트·일회용 상세 헤더 — 서비스 헤더와 같은 문법, 상태 어휘만 스크립트 축.
/// 실행 중이면 "실행"이 dedup(그 출력이 이미 여기 있다)이라 버튼을 감춘다 — 대신 ⟳ 재실행만 남긴다.
///
/// **별도 뷰인 이유**: 경과("12s")의 1초 tick을 이 헤더에 가둔다 — 도크 루트의 @State였을 땐
/// 매초 도크 본문 전체(목록·attach 터미널 update)가 리렌더됐다. tick은 **실행 중일 때만** 붙는다.
private struct ScriptDetailHeader: View {
    let state: AppState
    let item: LocatedScript
    let run: ScriptRun?
    /// 일회용이면 제목=명령(mono, 중복 명령줄 생략)이고, 재실행=새 기록·삭제=기록 삭제로 축이 바뀐다.
    var oneOff = false

    @State private var now = Date()

    var body: some View {
        if run?.isRunning == true {
            content.tick(every: 1, into: $now)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: ScriptStatusStyle.glyph(run?.state))
                .font(.muxa(.micro))
                .foregroundStyle(ScriptStatusStyle.color(run?.state))
                .frame(width: IconSize.statusSlot)
            // 일회용은 명령이 정체성이라 제목을 명령(mono)으로 — 아래 중복 명령줄은 생략한다.
            Text(oneOff ? item.script.command : item.script.name)
                .font(oneOff ? .muxaMono(.label) : .muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(oneOff ? .tail : .middle)
                .layoutPriority(oneOff ? -1 : 0)
                .modifier(FixedIf(oneOff == false))
            if let tail = ScriptStatusStyle.tail(run, now: now) {
                Text(tail).font(.muxaMono(.caption)).foregroundStyle(ScriptStatusStyle.color(run?.state))
            }
            if !oneOff {
                Text(item.script.command)
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Spacer(minLength: Space.sm)
            if run?.isRunning != true {
                IconButton(icon: run == nil ? "play.fill" : "arrow.clockwise",
                           help: oneOff ? "다시 실행 — 같은 명령을 새 기록으로"
                                        : (run == nil ? "실행" : "다시 실행 — 이전 로그는 사라집니다")) {
                    if oneOff { state.runOneOff(command: item.script.command) }
                    else { state.runScript(item.script, in: item.projectId) }
                }
                if oneOff {
                    IconButton(icon: "plus.square", help: "스크립트로 등록") { state.promoteOneOff(item.id) }
                }
            }
            if oneOff {
                // 일회용은 저위험(등록 아님·세션 한정)이라 확인 없이 — 마찰을 늘리지 않는다.
                IconButton(icon: "trash", help: "기록 삭제") { state.removeOneOff(item.id) }
            } else {
                // 등록 해제는 되돌릴 수 없는 파괴 — 2단계 확인으로 감싼다.
                DeleteConfirmButton(help: "등록 해제",
                                    prompt: run?.isRunning == true
                                        ? "실행 중인 \(item.script.name)을 종료하고 등록·로그를 지웁니다."
                                        : "\(item.script.name)의 등록과 종료 로그를 지웁니다.",
                                    confirmLabel: "등록 해제") {
                    state.removeScript(item.id, from: item.projectId)
                }
            }
        }
        .panelBar(height: RowHeight.panelHeader)
        .background(Color.pPanel)
    }
}

/// `fixedSize(horizontal:)`를 조건부로 — 등록 스크립트 이름은 자연 폭(fixedSize), 일회용 명령은 늘여 자른다.
private struct FixedIf: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View {
        if on { content.fixedSize() } else { content }
    }
}
