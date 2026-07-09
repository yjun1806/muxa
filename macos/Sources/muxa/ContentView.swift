import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | 활성 워크스페이스(Bonsplit)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다. 분할·탭은 Bonsplit이 관리한다.
struct ContentView: View {
    let state: AppState
    let home: String

    var body: some View {
        HStack(spacing: 0) {
            SidebarSUI(state: state)
            Rectangle().fill(Color.pBorder).frame(width: 1)
            workspaceArea
        }
        .background(Color.pPanel)
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
