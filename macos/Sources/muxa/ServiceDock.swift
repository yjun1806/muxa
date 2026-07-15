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
    /// 지금 상세로 보고 있는 서비스 — 없으면 첫 번째.
    private var selected: LocatedService? {
        all.first { $0.id == state.selectedServiceId } ?? all.first
    }
    /// 워크스페이스 2단으로 묶는다 — 현재 워크스페이스 위·풀강도, 타 워크스페이스는 muted 헤더로 강등.
    private var scopes: [ServiceScope] {
        groupByWorkspace(all, currentWorkspaceId: state.activeId,
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
        } else if all.isEmpty {
            VStack(spacing: 0) { toolbar(showAdd: true); HDivider(); emptyState }
        } else {
            HStack(spacing: 0) {
                ResizableLeftColumn(width: state.serviceListWidth,
                                    range: AppState.serviceListWidthRange) { w in
                    state.setServiceListWidth(w)
                } content: {
                    listColumn
                }
                if let service = selected { detail(service) }
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
                    ForEach(scopes) { scopeSection($0) }
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

    /// 워크스페이스 한 묶음 — 컨테이너 머리글(사이드바와 같은 `square.stack` + 대문자 라벨) 아래
    /// 프로젝트/서비스를 편다. 타 워크스페이스는 muted로 강등(색이 아니라 명도 — 색맹 안전, DESIGN §2·§5).
    private func scopeSection(_ scope: ServiceScope) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.xs) {
                // 채운 글리프 = "여기/내 것"(현재), 빈 글리프 = 다른 워크스페이스 — 색이 아니라 **모양**으로도
                // 갈라 색맹에 안전하다(DESIGN §2). 색은 pFg/pMuted 명도차로 한 번 더 말한다.
                Image(systemName: scope.isCurrent ? "square.stack.fill" : "square.stack")
                    .font(.muxa(.micro))
                    .foregroundStyle(scope.isCurrent ? Color.pFg : Color.pMuted)
                Text(scope.workspaceName)
                    .font(.muxaLabel).tracking(Tracking.label).textCase(.uppercase)
                    .foregroundStyle(scope.isCurrent ? Color.pFg : Color.pMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.sm)
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
            }
        }
        // 현재 워크스페이스는 pPanel(크롬) 위에 pBg **콘텐츠 카드**로 묶어 "여기/내 것" 영역을 만든다
        // (색이 아니라 명도·경계 — 색맹 안전, DESIGN §2 "콘텐츠는 그 위에 카드로 떠 있다"). 1px pBorder로
        // 경계를 못박는다. 타 워크스페이스는 크롬 위에 그대로 평평하게 둔다(같은 인셋으로 정렬만 맞춘다).
        .padding(.vertical, scope.isCurrent ? Space.sm : 0)
        .background {
            if scope.isCurrent {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color.pBg)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
            }
        }
        .padding(.horizontal, Space.xs)
    }

    /// 목록 행 — 팝오버와 같던 `ServiceRow`. 클릭하면 **전환 없이** 상세를 이 서비스로 바꾼다.
    private func row(_ item: LocatedService) -> some View {
        ServiceRow(service: item.service,
                   status: state.serviceMonitor.state(of: item.service.id),
                   port: state.serviceMonitor.ports[item.service.id],
                   selected: selected?.id == item.service.id) {
            state.selectedServiceId = item.service.id
        }
    }

    // MARK: 우 — 로그 헤더 + 실제 터미널(tmux attach)

    @ViewBuilder
    private func detail(_ item: LocatedService) -> some View {
        VStack(spacing: 0) {
            header(item)
            if isDead(item) {
                // 죽었으면 읽기 전용 로그 — 터미널을 붙이지 않는다(ServiceLogView 주석).
                ServiceLogView(projectId: item.projectId, serviceId: item.service.id,
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
