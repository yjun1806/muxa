import SwiftUI

/// 서비스 도크 — 탐색기·Git과 같은 **우측 도킹 패널**. 본문(터미널)을 밀어내고 좌측 경계로 너비를
/// 조절한다(`ContentView.serviceDock`이 `ResizablePanel`로 감싼다).
///
/// **[좌: 서비스 목록 | 우: 로그/터미널]** 좌우로 나눈다 — 목록은 얇은 사이드바(이름·상태),
/// 터미널은 전체 높이를 써 로그가 넓게 읽힌다. 목록↔터미널 사이는 `ResizableLeftColumn`으로 폭 조절.
///
/// **목록은 창 전체다**(모든 워크스페이스·프로젝트). 다른 워크스페이스의 dev 서버가 죽어도 여기서
/// 바로 보이고, 클릭하면 **활성 프로젝트 전환 없이** 그 자리에서 로그/터미널이 뜬다(`LocatedService.cwd`).
struct ServiceDock: View {
    let state: AppState

    @State private var showAdd = false

    /// 창 전체 서비스(모든 워크스페이스·프로젝트).
    private var all: [LocatedService] { state.allLocatedServices }
    /// 창 전체 스크립트 — 서비스와 한 목록에 산다(끝이 있는 명령이라 상태 어휘만 다르다).
    private var allScripts: [LocatedScript] { state.allLocatedScripts }

    /// 도크가 상세로 보여줄 수 있는 것 — 서비스 또는 스크립트(선택 id는 한 필드를 공유한다. id는 UUID라
    /// 충돌하지 않고, "지금 보는 것 하나"라는 의미도 같다).
    private enum Selection {
        case service(LocatedService)
        case script(LocatedScript)
    }

    /// 지금 상세로 보고 있는 것 — 없으면 첫 서비스, 그것도 없으면 첫 스크립트.
    private var selected: Selection? {
        if let id = state.selectedServiceId {
            if let service = all.first(where: { $0.id == id }) { return .service(service) }
            if let script = allScripts.first(where: { $0.id == id }) { return .script(script) }
        }
        return all.first.map(Selection.service) ?? allScripts.first.map(Selection.script)
    }

    /// 워크스페이스 2단으로 묶는다 — 현재 워크스페이스 위·풀강도, 타 워크스페이스는 muted 헤더로 강등.
    private var scopes: [ServiceScope] {
        groupByWorkspace(all, scripts: allScripts, currentWorkspaceId: state.activeId,
                         currentProjectId: state.activeProject?.id ?? "")
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.pPanel)
            .sheet(isPresented: $showAdd) {
                // 추가 대상은 **활성 프로젝트**다 — cwd를 넘겨 package.json 스크립트를 찾게 한다.
                ServiceAddSheet(cwd: state.activeProjectCwd) { name, command in
                    guard let pid = state.activeProject?.id, let cwd = state.activeProjectCwd else { return }
                    state.addService(name: name, command: command, to: pid, cwd: cwd)
                }
            }
            // 팝오버 대신 이 도크의 "+"로만 추가한다. 요청은 원샷(두 번 뜨지 않게 소비).
            .onChange(of: state.serviceAddRequested, initial: true) { _, requested in
                guard requested else { return }
                state.serviceAddRequested = false
                showAdd = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if !state.servicesAvailable {
            VStack(spacing: 0) { toolbar(showAdd: false); HDivider(); setup }
        } else if all.isEmpty, allScripts.isEmpty {
            VStack(spacing: 0) { toolbar(showAdd: true); HDivider(); emptyState }
        } else {
            HStack(spacing: 0) {
                ResizableLeftColumn(width: state.serviceListWidth,
                                    range: AppState.serviceListWidthRange) { w in
                    state.setServiceListWidth(w)
                } content: {
                    listColumn
                }
                switch selected {
                case .service(let service): detail(service)
                case .script(let script): scriptDetail(script)
                case .none: EmptyView()
                }
            }
        }
    }

    // MARK: 좌 — 서비스 목록(창 전체 · 워크스페이스 2단)

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar(showAdd: true)
            HDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.groupGap) {
                    ForEach(scopes) { scope in
                        if scope.isCurrent { currentScope(scope) } else { otherScope(scope) }
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
    }

    /// 목록 상단 바 — 제목 · 추가 · 닫기(항상 보이는 이 바가 닫기를 소유한다).
    private func toolbar(showAdd add: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Text("서비스").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            Spacer(minLength: Space.xs)
            if add, state.servicesAvailable {
                IconButton(icon: "plus", help: "서비스 추가") { showAdd = true }
            }
            IconButton(icon: "xmark", help: "서랍 닫기 (⌘J) — 프로세스는 계속 돕니다") {
                state.closeServiceDock()
            }
        }
        .panelBar(height: RowHeight.panelHeader)
    }

    /// 현재 워크스페이스 — pPanel(크롬) 위에 pBg **콘텐츠 카드**로 묶어 "여기/내 것" 영역을 만든다
    /// (색이 아니라 명도·경계 — 색맹 안전, DESIGN §2 "콘텐츠는 그 위에 카드로 떠 있다"). 늘 펼침.
    private func currentScope(_ scope: ServiceScope) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            scopeHeader(scope, chevron: nil, collapsed: false)
            scopeItems(scope)
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, Space.sm) // 카드 안 선택이 테두리에서 숨 쉴 만큼만(과하지 않게)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.pBg)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        }
        .padding(.horizontal, Space.xs) // 카드가 도크 벽에서 뜨는 자리
    }

    /// 다른 워크스페이스 — 기본은 **접힘**(한 줄: chevron · 개수 · 롤업 상태). 펼치면 카드 없이 목록을 편다.
    /// 접어도 "다른 워크스페이스 죽음을 바로 본다"는 도크 취지가 안 죽게, 접힌 줄이 **롤업 글리프**를 문다
    /// (죽은 게 있으면 빨간 느낌표로 승격 — `ServiceStatusStyle.summarize` 규칙).
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
        .padding(.horizontal, Space.xs) // 카드 없는 스코프는 벽에 가깝게 — 바깥 여백을 넓히지 않는다
    }

    /// 스코프 머리글 — (옵션 chevron) · 레이어 글리프 · 대문자 이름 · (접혔으면 롤업 글리프+개수).
    private func scopeHeader(_ scope: ServiceScope, chevron: String?, collapsed: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if let chevron {
                Image(systemName: chevron).font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted).frame(width: IconSize.statusSlot)
            }
            // 채운 글리프 = "여기/내 것"(현재), 빈 글리프 = 다른 워크스페이스 — 모양으로도 갈라 색맹에 안전(§2).
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
        .padding(.horizontal, Space.sm) // 아래 행(ServiceRow 내부 인셋)과 글리프 시작선을 맞춘다
        .frame(minHeight: RowHeight.tight)
        .contentShape(Rectangle())
    }

    /// 스코프의 프로젝트 그룹 + 서비스·스크립트 행. 서비스가 위, 스크립트가 아래 —
    /// "늘 도는 것"과 "돌렸던 것"의 구분은 행의 상태 글리프 축(원형 vs 사각형)이 이미 말한다.
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
    /// 스크립트도 롤업에 넣는다: 실패 확정은 exited로, 실행 중은 running으로 — 접힌 다른
    /// 워크스페이스에서 빌드가 실패해도 여기서 바로 보인다(도크의 존재 이유).
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

    /// 목록 행 — 팝오버와 같던 `ServiceRow`. 클릭하면 **전환 없이** 상세를 이 서비스로 바꾼다.
    private func row(_ item: LocatedService) -> some View {
        ServiceRow(service: item.service,
                   status: state.serviceMonitor.state(of: item.service.id),
                   port: state.serviceMonitor.ports[item.service.id],
                   selected: selectedId == item.service.id) {
            state.selectedServiceId = item.service.id
        }
    }

    /// 스크립트 목록 행 — 서비스 행과 같은 문법, 상태 어휘만 스크립트 축(ScriptStatusStyle).
    private func scriptRow(_ item: LocatedScript) -> some View {
        ScriptDockRow(script: item.script, run: state.scriptRuns[item.id],
                      selected: selectedId == item.id) {
            state.selectedServiceId = item.id
        }
    }

    /// 지금 선택된 항목의 id — 행 강조가 서비스·스크립트 어느 쪽인지 몰라도 되게 한 겹 벗긴다.
    private var selectedId: String? {
        switch selected {
        case .service(let s): return s.id
        case .script(let s): return s.id
        case .none: return nil
        }
    }

    // MARK: 우 — 로그 헤더 + 실제 터미널(tmux attach)

    @ViewBuilder
    private func detail(_ item: LocatedService) -> some View {
        VStack(spacing: 0) {
            header(item)
            if isDead(item) {
                // 죽었으면 읽기 전용 로그 — 터미널을 붙이지 않는다(ServiceLogView 주석).
                ServiceLogView(session: ServiceSession.name(projectId: item.projectId,
                                                            serviceId: item.service.id),
                               reloadToken: "\(item.service.id)|\(state.serviceRestartSeq)")
            } else {
                // 살아있으면 진짜 터미널(tmux attach) — Ctrl+C로 죽이고 그 자리에서 디버깅한다.
                TerminalRepresentable(
                    term: state.dockTerm(serviceId: item.service.id, projectId: item.projectId, cwd: item.cwd),
                    onFocus: {}
                )
                .id(item.service.id) // 서비스를 바꾸면 그 서비스의 터미널로 갈아 끼운다
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 상세 헤더 — 상태 글리프 · 이름 · 포트/코드 꼬리표 · 명령 · 시작/재시작 · 제거.
    /// 상태를 **모양으로** 말한다(라이브 터미널인지 얼어붙은 로그인지 헤더만 봐도 안다).
    private func header(_ item: LocatedService) -> some View {
        let service = item.service
        let st = state.serviceMonitor.state(of: service.id)
        let port = state.serviceMonitor.ports[service.id]
        let notStarted: Bool = { if case .missing = st { return true }; return false }()
        return HStack(spacing: Space.sm) {
            Image(systemName: ServiceStatusStyle.glyph(st))
                .font(.muxa(.micro))
                .foregroundStyle(ServiceStatusStyle.color(st))
                .frame(width: IconSize.statusSlot)
            Text(service.name)
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .fixedSize()
            if let tail = ServiceStatusStyle.tail(st, port: port) {
                Text(tail).font(.muxaMono(.caption)).foregroundStyle(ServiceStatusStyle.color(st))
            }
            Text(service.command)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1) // 자리가 모자라면 여기부터 줄인다(버튼은 끝까지 남는다)
            Spacer(minLength: Space.sm)
            // `.missing`(한 번도 안 띄움)이면 "재시작"은 거짓말이라 "시작"으로 — 동작은 같다.
            IconButton(icon: notStarted ? "play.fill" : "arrow.clockwise",
                       help: notStarted ? "시작" : "재시작") {
                guard let cwd = item.cwd else { return }
                state.restartService(service.id, in: item.projectId, cwd: cwd)
            }
            IconButton(icon: "trash", help: "서비스 제거 — 등록을 지우고 프로세스도 종료합니다") {
                state.removeService(service.id, from: item.projectId)
            }
        }
        .panelBar(height: RowHeight.panelHeader)
        .background(Color.pPanel)
    }

    // MARK: 우 — 스크립트 상세 (실행 중 = attach 터미널 / 종료 = 보존된 로그 / 실행 전 = 안내)

    @ViewBuilder
    private func scriptDetail(_ item: LocatedScript) -> some View {
        let run = state.scriptRuns[item.id]
        VStack(spacing: 0) {
            ScriptDetailHeader(state: state, item: item, run: run)
            if run?.isRunning == true {
                // 실행 중이면 진짜 터미널(tmux attach) — Ctrl+C로 중단하고 그 자리에서 본다.
                TerminalRepresentable(
                    term: state.dockScriptTerm(scriptId: item.id, projectId: item.projectId, cwd: item.cwd),
                    onFocus: {}
                )
                // 스크립트 전환뿐 아니라 **세션 갈아엎기**(재실행 기동 완료 → restartSeq 증가)에도
                // 갈아 끼운다 — 기동 중에 만들어진 attach는 옛/부재 세션에 붙은 죽은 서피스다(runScript 주석).
                .id("\(item.id)|\(state.serviceRestartSeq)")
            } else if run != nil {
                // 끝났으면 읽기 전용 로그 — remain-on-exit가 보존한 마지막 화면(exit 사유가 여기 있다).
                ServiceLogView(session: ScriptSession.name(projectId: item.projectId, scriptId: item.id),
                               reloadToken: "\(item.id)|\(state.serviceRestartSeq)")
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

    // MARK: 빈/미설치 상태 (목록이 없을 때 detail 자리를 채운다)

    private var setup: some View {
        // tmux가 없으면 기능을 숨기는 대신 **왜 없는지 말하고 설치를 돕는다**.
        ServiceSetupView(state: state) { command in
            state.mainStore?.injectToTerminal(command) ?? false
        }
    }

    private var emptyState: some View {
        EmptyState(icon: "square.stack.3d.up",
                   title: "등록된 서비스가 없습니다",
                   subtitle: "dev 서버처럼 오래 도는 명령을 등록하면 여기서 로그를 봅니다.\nmuxa를 꺼도 프로세스는 계속 돕니다.") {
            Button("서비스 추가") { showAdd = true }
                .font(.muxa(.label))
        }
        .background(Color.pBg)
    }

    /// 죽었나 — tmux가 진실 원천이다. 아직 모르면(missing) 살아있다고 보고 attach를 시도한다
    /// (폴링 첫 바퀴 전이라도 도크가 빈 화면으로 뜨지 않게). **`isFailure`가 아니다** — 정상 종료(0)한
    /// pane에 attach하면 죽은 셸에 붙어 빈 화면이 뜨므로 exit 0도 죽음으로 본다.
    private func isDead(_ item: LocatedService) -> Bool {
        if case .exited = state.serviceMonitor.state(of: item.service.id) { return true }
        return false
    }
}

/// 스크립트 상세 헤더 — 서비스 헤더와 같은 문법, 상태 어휘만 스크립트 축.
/// 실행 중이면 "실행"이 dedup(그 출력이 이미 여기 있다)이라 버튼을 감춘다 — 대신 ⟳ 재실행만 남긴다.
///
/// **별도 뷰인 이유**: 경과("12s")의 1초 tick을 이 헤더에 가둔다 — 도크 루트의 @State였을 땐
/// 매초 도크 본문 전체(목록·attach 터미널 update)가 리렌더됐다. tick은 **실행 중일 때만** 붙는다
/// (끝난 스크립트의 duration·exit 꼬리표는 정적이라 시계가 필요 없다).
private struct ScriptDetailHeader: View {
    let state: AppState
    let item: LocatedScript
    let run: ScriptRun?

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
            Text(item.script.name)
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .fixedSize()
            if let tail = ScriptStatusStyle.tail(run, now: now) {
                Text(tail).font(.muxaMono(.caption)).foregroundStyle(ScriptStatusStyle.color(run?.state))
            }
            Text(item.script.command)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1) // 자리가 모자라면 여기부터 줄인다(버튼은 끝까지 남는다)
            Spacer(minLength: Space.sm)
            if run?.isRunning != true {
                IconButton(icon: run == nil ? "play.fill" : "arrow.clockwise",
                           help: run == nil ? "실행" : "다시 실행 — 이전 로그는 사라집니다") {
                    state.runScript(item.script, in: item.projectId)
                }
            }
            IconButton(icon: "trash", help: "등록 해제 — 실행 중이면 종료하고 로그도 지웁니다") {
                state.removeScript(item.id, from: item.projectId)
            }
        }
        .panelBar(height: RowHeight.panelHeader)
        .background(Color.pPanel)
    }
}
