import AppKit
import SwiftUI

/// 상단바 왼쪽 클러스터 — 사이드바 모드 메뉴 + 새 워크스페이스 메뉴.
/// (src/SidebarControls.tsx 이식) ContentView 상단바 한 줄에 프로젝트 탭과 함께 배치된다.
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
        }
        .padding(.horizontal, 8)
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
