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
            .padding(.trailing, Space.sm)
            .padding(.bottom, Space.xs)
    }

    /// 전체 폭 상단바 — 신호등 · 워드마크 · 사이드바 컨트롤 · 프로젝트 탭 · 우측 토글.
    /// fullSizeContentView라 콘텐츠가 타이틀바까지 올라오고, 신호등은 `TrafficLights`가 이 줄 중앙으로 내린다.
    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.md) {
            // 신호등 3개 + 왼쪽 여백(TrafficLights.leadingInset) 확보 — 워드마크가 버튼에 닿지 않게.
            Color.clear.frame(width: 76)
            wordmark
            TopBarControls(state: state, home: home)
            if let ws = state.activeWorkspace {
                // 워크스페이스 관리(사이드바 컨트롤)와 프로젝트 탭은 성격이 다른 영역이라 선으로 가른다.
                VDivider(height: 18)
                ProjectTabBar(state: state, workspace: ws)
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
        .frame(width: 24, height: 24)
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
        .frame(width: 24, height: 24)
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
