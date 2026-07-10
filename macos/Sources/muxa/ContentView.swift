import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | 활성 워크스페이스(Bonsplit)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다. 분할·탭은 Bonsplit이 관리한다.
struct ContentView: View {
    let state: AppState
    let home: String

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(Color.pBorder).frame(height: 1)
            // 사이드바는 오버레이로 떠 있고, 레이아웃엔 접힌 폭(baseWidth)만 예약한다 —
            // hover peek로 펼쳐져도 콘텐츠(워크스페이스)가 밀리지 않는다.
            HStack(spacing: 0) {
                Color.clear.frame(width: state.sidebarMode.baseWidth)
                Rectangle().fill(Color.pBorder).frame(width: 1)
                workspaceColumn
            }
            .overlay(alignment: .topLeading) {
                SidebarSUI(state: state)
            }
        }
        .background(Color.pPanel)
        // ⌘K 빠른 전환기 — 크롬 전체 위에 뜨는 오버레이(닫혀 있으면 아무것도 안 그린다).
        .overlay { QuickSwitcher(state: state) }
    }

    /// 전체 폭 상단바 한 줄 — 신호등 · 사이드바/워크스페이스 컨트롤 · 프로젝트 탭 · 우측 경로.
    /// 타이틀바와 프로젝트 헤더를 한 줄로 합친다(두 줄로 따로 놀지 않게). fullSizeContentView라
    /// 콘텐츠가 타이틀바까지 올라와 신호등이 이 줄 위에 뜬다.
    private var topBar: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 68) // 신호등 3개 확보
            TopBarControls(state: state, home: home)
            if let ws = state.activeWorkspace {
                Rectangle().fill(Color.pBorder).frame(width: 1, height: 16)
                ProjectTabBar(state: state, workspace: ws)
                Spacer(minLength: 12)
                AttentionBell(state: state)
                explorerToggle
                gitToggle
                // 우측: 워크스페이스 · 활성 프로젝트 실효 경로
                Text(displayPath(ws.activeProject?.path ?? ws.path, home: home))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.trailing, 12)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: 38)
        .background(Color.pPanel)
    }

    /// 파일 익스플로러 토글 버튼(상단바 우측).
    private var explorerToggle: some View {
        Button { state.toggleExplorer() } label: {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(state.showExplorer ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .background(state.showExplorer ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help("파일 익스플로러")
    }

    /// Git 패널 토글 버튼(상단바 우측).
    private var gitToggle: some View {
        Button { state.toggleGitPanel() } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(state.showGitPanel ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .background(state.showGitPanel ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
                    Rectangle().fill(Color.pBorder).frame(width: 1)
                    // 파일 클릭 → 뷰어 탭. 우클릭 "여기에서 터미널 열기" → 그 폴더로 새 프로젝트.
                    FileExplorerPanel(
                        root: project.path ?? ws.path,
                        revealPath: state.store(for: project, in: ws).lastOpenedFilePath,
                        revealSeq: state.store(for: project, in: ws).revealSeq,
                        onOpenFile: { state.store(for: project, in: ws).openFile($0) },
                        onOpenTerminal: { dir in state.addProject(name: basename(dir), path: dir) }
                    )
                }
                if state.showGitPanel {
                    Rectangle().fill(Color.pBorder).frame(width: 1)
                    // 파일/커밋 클릭 → 활성 프로젝트의 새 탭으로 diff를 연다(모달 아님).
                    GitPanel(
                        dir: project.path ?? ws.path,
                        sessionBase: project.sessionBaseHead,
                        onResetBaseline: { state.resetSessionBaseline(projectId: project.id, cwd: project.path ?? ws.path) },
                        onSendReview: { state.store(for: project, in: ws).injectToTerminal($0) }
                    ) { state.store(for: project, in: ws).openDiff($0) }
                }
            }
        } else {
            Color.pBg
        }
    }
}
