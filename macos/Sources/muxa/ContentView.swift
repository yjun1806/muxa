import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | 활성 워크스페이스(Bonsplit)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다. 분할·탭은 Bonsplit이 관리한다.
struct ContentView: View {
    let state: AppState
    let home: String

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
            StatusBar(state: state, home: home)
                .padding(.trailing, Space.sm)
                .padding(.bottom, Space.xs)
        }
        .background(Color.pPanel)
        // ⌘K 빠른 전환기 — 크롬 전체 위에 뜨는 오버레이(닫혀 있으면 아무것도 안 그린다).
        .overlay { QuickSwitcher(state: state) }
        // 워크트리 피커 — 시트는 **여기가** 소유한다. 여는 버튼(사이드바 행의 +)은 hover에서만 존재해서,
        // 시트를 그 행에 달면 마우스가 떠나 행이 사라지는 순간 시트도 함께 죽는다(AppState가 요청만 나른다).
        // 대상 워크스페이스가 없으면 아예 띄우지 않는다 — 내용도 닫기 버튼도 없는 빈 시트가 뜬다.
        .sheet(isPresented: Binding(get: { state.worktreePickerRequested && state.activeWorkspace != nil },
                                    set: { state.worktreePickerRequested = $0 })) {
            // 대상은 항상 **활성** 워크스페이스다 — +가 눌리는 즉시 setActiveId로 전환하기 때문.
            if let ws = state.activeWorkspace {
                WorktreePicker(dir: ws.path ?? SystemPaths.currentDir ?? SystemPaths.home) { name, path in
                    state.addProject(name: name, path: path)
                    state.worktreePickerRequested = false
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
        workspaceColumn
            .contentCard(radius: Radius.lg, border: Color.pBorder)
            // 서비스 도크는 카드 위에 겹친다 — 카드를 리사이즈하지 않으므로 여닫아도 ghostty 그리드가
            // 리플로우되지 않는다(레이아웃을 차지하는 도크였다면 열 때마다 터미널이 출렁인다).
            //
            // **contentCard 뒤에 얹는 이유**: 카드는 칸 강조 테두리를 클립 바깥 맨 위 레이어에 그린다
            // (ContentCard 주석 참조). 카드 *안쪽* 오버레이로 두면 그 테두리가 도크를 뚫고 지나간다.
            // 여기 두면 테두리보다 위에 온다. 대신 카드 클립을 못 받으므로 하단 모서리는 직접 깎는다.
            .overlay(alignment: .bottom) { serviceDock }
            // 왼쪽에 틈을 두지 않는다 — 사이드바가 카드에 **직접 그림자를 드리운다**(`SidebarSUI`).
            // 카드 앞을 비워 카드의 그림자를 보이게 하는 방법도 있었지만, 그러면 보이는 크롬 띠가
            // "사이드바 폭 + 틈"이 되어 항목의 좌우 대칭이 영영 안 맞는다(실측). 위 레이어가 아래로
            // 그늘을 던지는 게 물리적으로도 옳고, 폭 = 띠가 되어 가운데가 자명해진다.
            .padding(.trailing, Space.sm)
            .padding(.bottom, Space.xs)
    }

    @ViewBuilder
    private var serviceDock: some View {
        if state.showServiceDock, let ws = state.activeWorkspace, let project = ws.activeProject {
            ServiceDock(state: state, project: project, cwd: project.path ?? ws.path)
                // 카드의 라운드 클립 바깥이라 하단 모서리를 직접 맞춰 깎는다(카드 밖으로 삐져나오지 않게).
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Radius.lg,
                                                  bottomTrailingRadius: Radius.lg))
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
            if let ws = state.activeWorkspace {
                // 좌측(앱·워크스페이스 관리)과 우측(현재 위치 + 패널 토글)은 성격이 다른 영역이라 선으로 가른다.
                VDivider(height: 18)
                Breadcrumb(workspace: ws) // 표시 전용 — 전환은 사이드바 트리가 유일한 경로다
                Spacer(minLength: Space.lg)
                AttentionBell(state: state)
                explorerToggle
                gitToggle
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
        Button { state.toggleExplorer() } label: {
            Image(systemName: "folder")
                .font(.muxa(.body))
                .foregroundStyle(state.showExplorer ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .frame(width: IconSize.control, height: IconSize.control)
        .background(state.showExplorer ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .help("파일 익스플로러")
    }

    /// Git 패널 토글 버튼(상단바 우측).
    private var gitToggle: some View {
        Button { state.toggleGitPanel() } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.muxa(.body))
                .foregroundStyle(state.showGitPanel ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .frame(width: IconSize.control, height: IconSize.control)
        .background(state.showGitPanel ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .help("Git 패널")
    }

    /// 활성 워크스페이스 열 = 활성 프로젝트의 Bonsplit(터미널 탭·분할) + (옵션) 우측 Git 패널.
    @ViewBuilder
    private var workspaceColumn: some View {
        if let ws = state.activeWorkspace, let project = ws.activeProject {
            HStack(spacing: 0) {
                // 프로젝트별 안정 identity — 전환해도 store(터미널들)는 AppState가 유지한다.
                BonsplitWorkspaceView(store: state.store(for: project, in: ws))
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
        } else {
            Color.pBg
        }
    }
}
