import AppKit
import GhosttyKit
import SwiftUI

/// 앱 루트 UI. (src/App.tsx 이식) 상단바 + [사이드바 | (탭바 + 터미널 호스트)].
/// AppState(@Observable)를 관찰해 자동 갱신한다.
struct ContentView: View {
    let app: ghostty_app_t
    let state: AppState
    let home: String

    var body: some View {
        // 상단바(사이드바 모드·워크스페이스 정보)는 타이틀바 액세서리로 얹는다(main.swift).
        // 여기선 사이드바 | (탭바 + 터미널 호스트)만 그린다.
        HStack(spacing: 0) {
            SidebarSUI(state: state)
            Rectangle().fill(Color.pBorder).frame(width: 1)
            VStack(spacing: 0) {
                TabBarView(state: state)
                Rectangle().fill(Color.pBorder).frame(height: 1)
                WorkspaceHost(app: app, state: state)
            }
        }
        .background(Color.pPanel)
    }
}
