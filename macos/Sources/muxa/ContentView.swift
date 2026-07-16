import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | 활성 워크스페이스(Bonsplit)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다. 분할·탭은 Bonsplit이 관리한다.
struct ContentView: View {
    let state: AppState
    let home: String

    /// 사용량 칩 위치 설정 — 헤더에 놓을지 여부를 topBar가 이걸 읽어 정한다(@Observable).
    private let statusBarSettings = StatusBarSettings.shared

    var body: some View {
        // 크롬(상단바·사이드바·푸터)은 한 덩어리 배경이고, 그 위에 콘텐츠가 카드로 떠 있다.
        // 크롬끼리는 구분선을 넣지 않는다 — 같은 색으로 이어져야 "창 전체가 하나의 틀"로 읽힌다.
        // 콘텐츠와 크롬은 카드의 모서리·테두리가 구분한다(선을 긋지 않아도 층이 보인다).
        VStack(spacing: 0) {
            topBar
            // 사이드바는 오버레이로 떠 있고, 레이아웃엔 접힌 폭(baseWidth)만 예약한다 —
            // hover peek로 펼쳐져도 콘텐츠(워크스페이스)가 밀리지 않는다.
            HStack(spacing: 0) {
                Color.clear.frame(width: state.sidebarMode.baseWidth)
                contentCard
            }
            .overlay(alignment: .topLeading) {
                SidebarSUI(state: state)
            }
            // 푸터도 크롬이라 창 가장자리에 딱 붙이지 않는다 — 카드와 같은 여백 안에 놓는다.
            StatusBar(state: state)
                .padding(.trailing, Space.sm)
                .padding(.bottom, Space.xs)
        }
        .background(Color.pPanel)
        // ⌘K 빠른 전환기 — 크롬 전체 위에 뜨는 오버레이(닫혀 있으면 아무것도 안 그린다).
        .overlay { QuickSwitcher(state: state) }
        // 복원 후(워크스페이스가 디스크에서 로드된 뒤) 워크트리 감시자를 붙인다 — 첫 실행은 ensureInitial이 건다.
        .onAppear { state.syncWorktreeMonitor() }
        // 워크트리 피커 — 시트는 **여기가** 소유한다. 여는 버튼(사이드바 행의 +)은 hover에서만 존재해서,
        // 시트를 그 행에 달면 마우스가 떠나 행이 사라지는 순간 시트도 함께 죽는다(AppState가 요청만 나른다).
        // 대상 워크스페이스가 없으면 아예 띄우지 않는다 — 내용도 닫기 버튼도 없는 빈 시트가 뜬다.
        .sheet(isPresented: Binding(get: { state.worktreePickerRequested && state.activeWorkspace != nil },
                                    set: { state.worktreePickerRequested = $0 })) {
            // 대상은 항상 **활성** 워크스페이스다 — +가 눌리는 즉시 setActiveId로 전환하기 때문.
            if let ws = state.activeWorkspace {
                WorktreePicker(dir: ws.path ?? SystemPaths.home) { name, path in
                    state.addProject(name: name, path: path)
                    state.worktreePickerRequested = false
                } onRemoved: { path in
                    // 워크트리 폴더가 사라졌다 — 그 폴더를 쓰던 프로젝트를 닫는다(죽은 경로·좀비 dev 서버 방지).
                    state.closeProjects(underPath: path)
                } onCancel: {
                    state.worktreePickerRequested = false
                }
            }
        }
    }

    /// 콘텐츠 카드 — 터미널·패널이 사는 판. 크롬 배경 위에 얹혀 층이 드러난다.
    ///
    /// 콘텐츠는 카드 모서리로 정확히 클리핑한다(여백으로 밀어내지 않는다 — 터미널 주위에 흰 띠가
    /// 생기면 화면만 좁아진다). 칸의 강조 테두리는 그 클립에 깎이지 않도록 **클립 바깥**에서
    /// 그려진다(`contentCard(radius:)` → `ContentCard`). 카드 테두리 선은 그보다 아래에 깔아,
    /// 활성 칸의 테두리가 닿는 변에선 그 위를 덮게 한다.
    private var contentCard: some View {
        // 서비스 서랍은 **카드 안쪽 도킹 패널**이다(탐색기·Git과 같은 층) — 콘텐츠를 밀어내고,
        // 좌측 경계 드래그로 너비를 조절한다(`workspaceColumn`이 HStack으로 나란히 놓는다).
        workspaceColumn
            .contentCard(radius: Radius.lg, border: Color.pBorder)
            // 왼쪽에 틈을 두지 않는다 — 사이드바가 카드에 **직접 그림자를 드리운다**(`SidebarSUI`).
            // 카드 앞을 비워 카드의 그림자를 보이게 하는 방법도 있었지만, 그러면 보이는 크롬 띠가
            // "사이드바 폭 + 틈"이 되어 항목의 좌우 대칭이 영영 안 맞는다(실측). 위 레이어가 아래로
            // 그늘을 던지는 게 물리적으로도 옳고, 폭 = 띠가 되어 가운데가 자명해진다.
            .padding(.trailing, Space.sm)
            .padding(.bottom, Space.xs)
    }

    /// 서비스 서랍 — 탐색기·Git과 **같은 도킹 패널**(콘텐츠를 밀어내고 좌측 경계로 너비 리사이즈·영속).
    /// 스코프는 **도크를 연 프로젝트**다(`state.dockTarget`) — 분리 창의 서비스를 클릭해도 로그는 메인의
    /// 이 서랍에서 열리므로 메인의 활성 프로젝트와 다를 수 있다.
    @ViewBuilder
    private var serviceDock: some View {
        if state.showServiceDock {
            // 도크는 이제 **창 전체** 서비스를 스스로 그린다 — 특정 프로젝트에 매이지 않는다.
            ResizablePanel(width: state.serviceDockWidth, range: AppState.serviceDockWidthRange) { w in
                state.setServiceDockWidth(w, persist: true)
            } content: {
                ServiceDock(state: state)
            }
        }
    }

    /// 전체 폭 상단바 — 신호등 · 워드마크 · 사이드바 컨트롤 · 브레드크럼 · 우측 토글.
    /// fullSizeContentView라 콘텐츠가 타이틀바까지 올라오고, 신호등은 `TrafficLights`가 이 줄 중앙으로 내린다.
    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.md) {
            // 신호등 3개 + 왼쪽 여백 확보 — 워드마크가 버튼에 닿지 않게. 폭은 신호등 기하와 한 출처를 쓴다.
            Color.clear.frame(width: TrafficLights.reservedLeadingWidth)
            wordmark
            TopBarControls(state: state, home: home)
            // 사용량 칩이 헤더 왼쪽 설정이면 앱 컨트롤 옆에 둔다(계정 단위라 워크스페이스와 무관하게 뜬다).
            if statusBarSettings.position == .headerLeft { UsageChip(state: state) }
            if let ws = state.activeWorkspace {
                // 좌측(앱·워크스페이스 관리)과 우측(현재 위치 + 패널 토글)은 성격이 다른 영역이라 선으로 가른다.
                VDivider(height: 18)
                Breadcrumb(workspace: ws) // 표시 전용 — 전환은 사이드바 트리가 유일한 경로다
                // **선택한 프로젝트의 경로**(라이브 셸 pwd가 아니다) — 기본은 워크스페이스 경로,
                // 프로젝트(워크트리)를 바꾸면 그 워크트리 경로로 바뀐다. 브레드크럼(정체) 옆에 **조용히** 둔다:
                // 세로선 없이(HStack 간격만), 한 단 작고 더 흐리게(mono). 워크스페이스명은 사용자가 자유
                // 수정하므로 경로 꼬리와 겹칠 수도 안 겹칠 수도 있어, 전체경로를 접지 않고 그대로 보여준다.
                if let path = ws.activeProject?.path ?? ws.path {
                    Text(displayPath(path, home: home))
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(-1) // 길면 여기부터 줄인다(벨·토글은 끝까지 남는다)
                        .help(path)
                }
                Spacer(minLength: Space.lg)
                // 사용량 칩이 헤더 오른쪽 설정이면 벨·토글 앞에 둔다.
                if statusBarSettings.position == .headerRight { UsageChip(state: state) }
                AttentionBell(state: state)
                explorerToggle
                gitToggle
                settingsButton
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.topBar)
    }

    /// 워드마크 — 창에 앱 이름을 남긴다(타이틀바를 숨겼으므로 여기가 유일한 자리).
    /// 개발 빌드면 DEV 배지를 달아, 설치된 muxa.app과 나란히 떠 있어도 어느 창인지 바로 구분된다(AppInfo).
    private var wordmark: some View {
        HStack(spacing: Space.sm) {
            Text("Muxa")
                .font(.muxa(.title, weight: .semibold))
                .foregroundStyle(Color.pFg)
            if AppInfo.isDev {
                Pill(color: Color.pBorderActivity) {
                    Text("DEV").font(.muxa(.nano, weight: .bold))
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, Space.xs)
        .help(AppInfo.name)
    }

    /// 파일 익스플로러 토글 버튼(상단바 우측).
    private var explorerToggle: some View {
        PanelToggle(icon: "folder", on: state.showExplorer, help: "파일 익스플로러") {
            state.toggleExplorer()
        }
    }

    /// Git 패널 토글 버튼(상단바 우측).
    private var gitToggle: some View {
        PanelToggle(icon: "arrow.triangle.branch", on: state.showGitPanel, help: "Git 패널") {
            state.toggleGitPanel()
        }
    }

    /// 설정 사이드 패널 토글 — 탭 스타일·사용량 표시를 담은 도킹 패널을 연다/닫는다.
    private var settingsButton: some View {
        PanelToggle(icon: "gearshape", on: state.showSettings, help: "설정") {
            state.toggleSettings()
        }
    }

    /// 활성 워크스페이스 열 = 활성 프로젝트의 Bonsplit(터미널 탭·분할) + (옵션) 우측 Git 패널.
    ///
    /// **소유권 가드**: 그 프로젝트가 분리 창에 있으면 여기선 그리지 않는다(I3 — 한 스토어는 정확히
    /// 한 창의 뷰 트리에서만 렌더된다). 대신 되돌릴 길을 주는 플레이스홀더를 그린다.
    private var workspaceColumn: some View {
        // 서비스 서랍은 본문 오른쪽에 도킹 사이블링으로 붙어 본문을 밀어낸다(탐색기·Git과 같은 층).
        // `mainColumn`(본문)이 프로젝트 열이든 되돌리기 카드든, 서랍은 그 오른쪽에 동일하게 붙는다.
        HStack(spacing: 0) {
            mainColumn
            serviceDock
            settingsDock
        }
    }

    /// 설정 서랍 — 탐색기·Git·서비스와 같은 도킹 패널(콘텐츠를 밀어내고 좌측 경계로 폭 조절).
    /// 앱 전역 설정이라 프로젝트와 무관하게 뜬다(workspaceColumn 오른쪽 끝).
    @ViewBuilder
    private var settingsDock: some View {
        if state.showSettings {
            ResizablePanel(width: state.settingsPanelWidth, range: AppState.settingsPanelWidthRange) { w in
                state.setSettingsPanelWidth(w, persist: true)
            } content: {
                SettingsPanel(state: state)
            }
        }
    }

    @ViewBuilder
    private var mainColumn: some View {
        if let ws = state.activeWorkspace, let project = ws.activeProject {
            if state.owner(of: project.id).isMain {
                projectColumn(ws, project)
            } else {
                SeparatedPlaceholder(state: state, project: project)
            }
        } else {
            Color.pBg
        }
    }

    /// 메인 창이 소유한 프로젝트의 본문.
    private func projectColumn(_ ws: Workspace, _ project: Project) -> some View {
        HStack(spacing: 0) {
            // 프로젝트별 안정 identity — 전환해도 store(터미널들)는 AppState가 유지한다.
            BonsplitWorkspaceView(store: state.store(for: project, in: ws),
                                  windowId: WindowID.main.rawValue)
                .id(project.id)
            if state.showExplorer {
                // 좌측 경계 드래그로 폭 조절(손 뗄 때 영속). 파일 클릭 → 뷰어 탭. 우클릭 "여기에서 터미널 열기".
                ResizablePanel(width: state.explorerWidth, range: AppState.panelWidthRange) { w in
                    state.setExplorerWidth(w, persist: true)
                } content: {
                    FileExplorerPanel(
                        root: project.path ?? ws.path,
                        revealPath: state.store(for: project, in: ws).lastOpenedFilePath,
                        revealSeq: state.store(for: project, in: ws).revealSeq,
                        onOpenFile: { state.store(for: project, in: ws).openFile($0) },
                        onOpenTerminal: { dir in state.addProject(name: basename(dir), path: dir) }
                    )
                }
            }
            if state.showGitPanel {
                // 파일/커밋 클릭 → 활성 프로젝트의 새 탭으로 diff를 연다(모달 아님). 좌측 경계로 폭 조절.
                ResizablePanel(width: state.gitPanelWidth, range: AppState.gitPanelWidthRange) { w in
                    state.setGitPanelWidth(w, persist: true)
                } content: {
                    GitPanel(
                        dir: project.path ?? ws.path,
                        sessionBase: project.sessionBaseHead,
                        onResetBaseline: { state.resetSessionBaseline(projectId: project.id, cwd: project.path ?? ws.path) },
                        onSendReview: { state.store(for: project, in: ws).injectToTerminal($0) }
                    ) { state.store(for: project, in: ws).openDiff($0) }
                }
            }
        }
    }
}
