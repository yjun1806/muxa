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
    @State private var suggestions: [String] = []

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
        case .scripts:
            if let id = state.selectedServiceId, let s = allScripts.first(where: { $0.id == id }) { return .script(s) }
            return allScripts.first.map(Selection.script)
        case .oneoff:
            if let id = state.selectedServiceId, let s = oneOff.first(where: { $0.id == id }) { return .oneoff(s) }
            return oneOff.last.map(Selection.oneoff) // 최근이 뒤 → 기본은 최근 실행
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
        case .scripts:  return groupByWorkspace([], scripts: allScripts, currentWorkspaceId: state.activeId, currentProjectId: cur)
        case .oneoff:   return []
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

    /// 도크 상단 **전폭** 바 — [탭 스위처] ····· [✕(⌘J)]. **추가·비우기는 여기 두지 않는다**(＋가 탭 옆이면
    /// "탭 추가"로 오독). 추가는 현재 워크스페이스 카드 안, 일회용 비우기는 그 탭 목록 헤더가 맡는다.
    private var dockTopBar: some View {
        HStack(spacing: Space.sm) {
            tabSwitcher
            Spacer(minLength: Space.xs)
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
            case .services, .scripts: scopeList
            case .oneoff: oneOffColumn
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
        case .scripts:  return allScripts.contains { state.scriptRuns[$0.id]?.isFailure == true }
        case .oneoff:   return oneOff.contains { state.scriptRuns[$0.id]?.isFailure == true }
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
                Text(tab == .scripts ? "등록된 스크립트가 없습니다." : "등록된 서비스가 없습니다.")
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .padding(.horizontal, Space.sm).padding(.top, Space.tight)
            }
            if state.activeProject != nil {
                AddInCardRow(kind: tab, projectName: state.activeProject?.name ?? "") {
                    if tab == .scripts { scriptPrefill = ""; showScriptAdd = true } else { showServiceAdd = true }
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

    private var oneOffColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            oneOffInput
            HDivider()
            if oneOff.isEmpty {
                oneOffEmpty
            } else {
                oneOffHistoryHeader
                oneOffHistory
            }
        }
        .tick(every: 1, into: $now)
        .task(id: state.activeProjectCwd) {
            // 프로젝트 감지 → 설치 명령 제안(빈 상태의 채움 칩). 매니저를 모르면 제안 없음.
            let found = ProjectScripts.discover(in: state.activeProjectCwd)
            suggestions = found.manager.map { ["\($0.rawValue) install"] } ?? []
        }
    }

    /// 명령 입력창 + [실행] — Return으로도 실행. 스크래치 스트립은 스크롤에 안 딸려 온다(늘 최상단).
    private var oneOffInput: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Image(systemName: "chevron.right")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted).frame(width: IconSize.statusSlot)
                TextField("pnpm install · brew install … — 한 번 실행", text: $oneOffCommand)
                    .textFieldStyle(.plain)
                    .font(.muxaMono(.body))
                    .foregroundStyle(Color.pFg)
                    .focused($oneOffFocused)
                    .onSubmit(runOneOff)
                    .accessibilityLabel("한 번 실행할 명령")
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.toolbar)
            .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: RowHeight.hairline))

            Button(action: runOneOff) {
                Text("실행")
                    .font(.muxa(.label))
                    .foregroundStyle(canRunOneOff ? Color.pOnBrand : Color.pMuted)
                    .padding(.horizontal, Space.sm)
                    .frame(height: RowHeight.toolbar)
                    .background(canRunOneOff ? Color.pBrand : Color.pBtnHover,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .disabled(!canRunOneOff)
            .help("한 번 실행 (Return)")
            .accessibilityLabel("실행")
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.sm)
    }

    private var canRunOneOff: Bool {
        !oneOffCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runOneOff() {
        guard canRunOneOff else { return }
        state.runOneOff(command: oneOffCommand)
        oneOffCommand = ""
    }

    /// 최근 실행 헤더 — "비우기"가 여기 산다(툴바가 아니라 비우는 대상 바로 위). 완료분만·실행 중 보존.
    private var oneOffHistoryHeader: some View {
        HStack(spacing: Space.sm) {
            Text("최근 실행")
                .font(.muxa(.micro, weight: .semibold)).tracking(Tracking.label)
                .textCase(.uppercase).foregroundStyle(Color.pMuted)
            Spacer(minLength: Space.sm)
            if oneOff.contains(where: { state.scriptRuns[$0.id]?.isRunning != true }) {
                Button { state.clearOneOffHistory() } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "wind").font(.muxa(.micro))
                        Text("비우기").font(.muxa(.caption))
                    }
                    .foregroundStyle(Color.pMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).clickCursor()
                .help("완료된 일회용 기록만 비웁니다 — 실행 중은 보존")
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.tight)
    }

    /// 최근 실행 기록 — 최신이 위(역시간순 flat). 스코프 카드 없음(소수·휘발).
    private var oneOffHistory: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(oneOff.reversed())) { item in
                    OneOffRow(script: item.script, run: state.scriptRuns[item.id], now: now,
                              selected: selectedId == item.id,
                              action: { state.selectedServiceId = item.id },
                              onRun: { state.runOneOff(command: item.script.command) },
                              onPromote: { state.promoteOneOff(item.id) },
                              onDelete: { state.removeOneOff(item.id) })
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    /// 기록 0 — 입력창은 위에 그대로 두고, 아래에 가벼운 안내 + 프로젝트 감지 채움 칩(클릭=입력, 실행 아님).
    private var oneOffEmpty: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.tight) {
                Text("아직 실행한 일회용 명령이 없습니다")
                    .font(.muxa(.label, weight: .semibold)).foregroundStyle(Color.pFg)
                Text("위에 명령을 적고 실행하면 백그라운드에서 한 번 돌고, 출력·종료 로그가 여기 남습니다. 자주 쓰면 기록에서 등록으로 스크립트에 올립니다.")
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !suggestions.isEmpty {
                Text("이 프로젝트")
                    .font(.muxa(.micro, weight: .semibold)).tracking(Tracking.label)
                    .foregroundStyle(Color.pMuted)
                ForEach(suggestions, id: \.self) { cmd in
                    Button { oneOffCommand = cmd; oneOffFocused = true } label: {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "arrow.up.left").font(.muxa(.micro))
                            Text(cmd).font(.muxaMono(.caption))
                        }
                        .foregroundStyle(Color.pFg)
                        .padding(.horizontal, Space.sm).padding(.vertical, Space.tight)
                        .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: RowHeight.hairline))
                        .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain).clickCursor()
                    .help("명령 채우기(실행 아님)")
                    .accessibilityLabel("명령 채우기: \(cmd)")
                }
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 우 — 상세 (선택 종류별)

    @ViewBuilder
    private var detailColumn: some View {
        switch selected {
        case .service(let s): detail(s)
        case .script(let s): scriptDetail(s, oneOff: false)
        case .oneoff(let s): scriptDetail(s, oneOff: true) // 같은 상세(attach·로그), 헤더 액션만 일회용 축
        case .none:
            ZStack {
                Color.pBg
                Text(tab == .oneoff ? "명령을 실행하면 여기에 출력이 보입니다"
                                    : "왼쪽에서 항목을 선택하면 로그가 보입니다")
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detail(_ item: LocatedService) -> some View {
        let st = state.serviceMonitor.state(of: item.service.id)
        let stopped = state.userStoppedServiceIds.contains(item.service.id)
        // 로그를 보여줄 때: 죽었거나(exited), 사용자가 중단해(세션 kill → missing) attach할 게 없을 때.
        let showLog: Bool = { if case .exited = st { return true }; return stopped && st == .missing }()
        VStack(spacing: 0) {
            header(item)
            if showLog {
                ServiceLogView(session: ServiceSession.name(projectId: item.projectId,
                                                            serviceId: item.service.id),
                               // finalLogs 도착 시 다시 읽도록 토큰에 존재 여부를 실어 준다.
                               reloadToken: "\(item.service.id)|\(state.serviceRestartSeq)|\(state.finalLogs[item.service.id] != nil)",
                               fallback: state.finalLogs[item.service.id])
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
            if run?.isRunning == true {
                TerminalRepresentable(
                    term: state.dockScriptTerm(scriptId: item.id, projectId: item.projectId, cwd: item.cwd),
                    onFocus: {}
                )
                .id("\(item.id)|\(state.serviceRestartSeq)")
            } else if run != nil {
                ServiceLogView(session: ScriptSession.name(projectId: item.projectId, scriptId: item.id),
                               reloadToken: "\(item.id)|\(state.serviceRestartSeq)|\(state.finalLogs[item.id] != nil)",
                               fallback: state.finalLogs[item.id])
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

    private var label: String { kind == .scripts ? "스크립트 추가" : "서비스 추가" }

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
