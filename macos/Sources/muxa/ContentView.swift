import AppKit
import GhosttyKit
import SwiftUI

/// 앱 크롬 UI. (src/App.tsx 이식) [사이드바 | (탭바 + 터미널 자리)].
/// 상단바는 타이틀바 액세서리(main.swift)로 얹는다.
///
/// 터미널은 이 SwiftUI 트리 안에 두지 않는다 — 분할 시 터미널 내부 레이아웃이
/// SwiftUI 제약 패스를 재귀 무효화해 창이 크래시하기 때문. 대신 "터미널 자리"를
/// 빈 영역으로 두고 그 프레임만 onTerminalFrame으로 알려, AppKit 형제 뷰(RootView)가
/// 그 자리에 실제 터미널 호스트를 얹는다. (DESIGN.md D16)
struct ContentView: View {
    let app: ghostty_app_t
    let state: AppState
    let home: String
    let onTerminalFrame: (CGRect) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarSUI(state: state)
            Rectangle().fill(Color.pBorder).frame(width: 1)
            VStack(spacing: 0) {
                TabBarView(state: state)
                Rectangle().fill(Color.pBorder).frame(height: 1)
                // 터미널 자리 — 실제 터미널은 AppKit 형제 뷰가 이 프레임에 겹쳐 그린다.
                Color.clear.overlay(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TerminalFrameKey.self,
                            value: geo.frame(in: .named("root"))
                        )
                    }
                )
            }
        }
        .background(Color.pPanel)
        .coordinateSpace(name: "root")
        .onPreferenceChange(TerminalFrameKey.self) { onTerminalFrame($0) }
    }
}

/// 터미널 자리의 프레임(크롬 루트 좌표계)을 상위로 전달하는 프레퍼런스 키.
private struct TerminalFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
