import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | 활성 워크스페이스(Bonsplit)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다. 분할·탭은 Bonsplit이 관리한다.
struct ContentView: View {
    let state: AppState
    let home: String

    var body: some View {
        // 사이드바는 오버레이로 떠 있고, 레이아웃엔 접힌 폭(baseWidth)만 예약한다 —
        // hover peek로 펼쳐져도 콘텐츠(워크스페이스)가 밀리지 않는다.
        HStack(spacing: 0) {
            Color.clear.frame(width: state.sidebarMode.baseWidth)
            Rectangle().fill(Color.pBorder).frame(width: 1)
            workspaceArea
        }
        .background(Color.pPanel)
        .overlay(alignment: .topLeading) {
            SidebarSUI(state: state)
        }
    }

    @ViewBuilder
    private var workspaceArea: some View {
        if let ws = state.activeWorkspace {
            // 워크스페이스별 안정 identity — 전환해도 store(터미널들)는 AppState가 유지한다.
            BonsplitWorkspaceView(store: state.store(for: ws))
                .id(ws.id)
        } else {
            Color.pBg
        }
    }
}
