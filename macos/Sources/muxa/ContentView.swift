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
            Rectangle().fill(Color.pBorder).frame(height: 1)
            HStack(spacing: 0) {
                SidebarSUI(state: state)
                Rectangle().fill(Color.pBorder).frame(width: 1)
                VStack(spacing: 0) {
                    TabBarView(state: state)
                    Rectangle().fill(Color.pBorder).frame(height: 1)
                    WorkspaceHost(app: app, state: state)
                }
            }
        }
        .background(Color.pPanel)
        .ignoresSafeArea() // 타이틀바 영역까지 콘텐츠가 차지 (상단바가 신호등 줄에)
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
/// 웹 `.topbar`: panel 회색, 28px, 좌측 72px 신호등 자리, 워크스페이스 정보는 좌측 경계선으로 구분.
private struct TopBarSUI: View {
    let state: AppState
    let home: String
    let pickFolder: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 72) // 신호등 영역

            Menu {
                Picker("사이드바", selection: sidebarBinding) {
                    ForEach(SidebarMode.allCases, id: \.self) { mode in
                        Text("\(mode.label) — \(mode.hint)").tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(Color.pMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("사이드바 표시 모드")

            Menu {
                Button {
                    state.addWorkspace(path: home)
                } label: {
                    Label("홈에서 열기", systemImage: "house")
                }
                Button {
                    pickFolder()
                } label: {
                    Label("폴더 선택…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.pMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("새 워크스페이스")

            if let ws = state.activeWorkspace {
                Rectangle().fill(Color.pBorder).frame(width: 1, height: 16)
                    .padding(.horizontal, 6)
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pMuted)
                Text(ws.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.pFg)
                Text(displayPath(ws.path, home: home))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 28) // 신호등 줄 높이에 맞춤 (Tauri식)
        .background(Color.pPanel)
    }

    private var sidebarBinding: Binding<SidebarMode> {
        Binding(get: { state.sidebarMode }, set: { state.setSidebarMode($0) })
    }
}
