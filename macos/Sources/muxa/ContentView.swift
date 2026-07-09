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
        VStack(spacing: 0) {
            TopBarSUI(state: state, home: home, pickFolder: pickFolder)
            Divider()
            HStack(spacing: 0) {
                SidebarSUI(state: state)
                Divider()
                VStack(spacing: 0) {
                    TabBarView(state: state)
                    Divider()
                    WorkspaceHost(app: app, state: state)
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: home)
        if panel.runModal() == .OK, let url = panel.url {
            state.addWorkspace(path: url.path)
        }
    }
}

/// 상단바 — 사이드바 모드·새 워크스페이스 메뉴 + 활성 워크스페이스 이름/경로. (TopBar.tsx + SidebarControls.tsx)
private struct TopBarSUI: View {
    let state: AppState
    let home: String
    let pickFolder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 64) // 신호등 영역

            Menu {
                ForEach(SidebarMode.allCases, id: \.self) { mode in
                    Button {
                        state.setSidebarMode(mode)
                    } label: {
                        Label("\(mode.label) — \(mode.hint)",
                              systemImage: state.sidebarMode == mode ? "checkmark" : "")
                    }
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            Menu {
                Button("홈에서 열기") { state.addWorkspace(path: home) }
                Button("폴더 선택…") { pickFolder() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            if let ws = state.activeWorkspace {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(ws.name).font(.system(size: 12, weight: .semibold))
                Text(displayPath(ws.path, home: home))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
