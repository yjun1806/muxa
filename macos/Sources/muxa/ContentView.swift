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
    }

    /// 전체 폭 상단바 — 신호등(좌상단) 자리를 비우고 그 오른쪽에 컨트롤을 둔다.
    /// fullSizeContentView라 콘텐츠가 타이틀바까지 올라와 신호등이 이 줄 위에 뜬다.
    private var topBar: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 72) // 신호등 3개 확보
            TopBarControls(state: state, home: home)
            Spacer(minLength: 0)
        }
        .frame(height: 32)
        .background(Color.pPanel)
    }

    /// 활성 워크스페이스 열 = 프로젝트 탭바 + 활성 프로젝트의 Bonsplit(탭·분할).
    @ViewBuilder
    private var workspaceColumn: some View {
        if let ws = state.activeWorkspace {
            VStack(spacing: 0) {
                ProjectTabBar(state: state, workspace: ws)
                Rectangle().fill(Color.pBorder).frame(height: 1)
                if let project = ws.activeProject {
                    // 프로젝트별 안정 identity — 전환해도 store(터미널들)는 AppState가 유지한다.
                    BonsplitWorkspaceView(store: state.store(for: project, in: ws))
                        .id(project.id)
                } else {
                    Color.pBg
                }
            }
        } else {
            Color.pBg
        }
    }
}
