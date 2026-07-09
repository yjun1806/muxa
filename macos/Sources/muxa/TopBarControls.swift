import AppKit
import SwiftUI

/// 타이틀바에 얹는 상단바 컨트롤 — 신호등 바로 오른쪽 같은 줄에 표시된다.
/// (src/SidebarControls.tsx + TopBar.tsx 이식) NSTitlebarAccessoryViewController.view로 호스팅한다.
/// SwiftUI 콘텐츠에 넣으면 타이틀바 프레임에 가려지므로, 액세서리로 직접 얹는다.
struct TopBarControls: View {
    let state: AppState
    let home: String

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Picker("사이드바", selection: sidebarBinding) {
                    ForEach(SidebarMode.allCases, id: \.self) { mode in
                        Text("\(mode.label) — \(mode.hint)").tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "sidebar.left").foregroundStyle(Color.pMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("사이드바 표시 모드")

            Menu {
                Button { state.addWorkspace(path: home) } label: {
                    Label("홈에서 열기", systemImage: "house")
                }
                Button { pickFolder() } label: {
                    Label("폴더 선택…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus").foregroundStyle(Color.pMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("새 워크스페이스")

            if let ws = state.activeWorkspace {
                Rectangle().fill(Color.pBorder).frame(width: 1, height: 16)
                    .padding(.horizontal, 6)
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Color.pMuted)
                Text(ws.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.pFg)
                // 실제 cwd는 활성 프로젝트 경로(없으면 워크스페이스 경로 상속)
                Text(displayPath(ws.activeProject?.path ?? ws.path, home: home))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sidebarBinding: Binding<SidebarMode> {
        Binding(get: { state.sidebarMode }, set: { state.setSidebarMode($0) })
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
