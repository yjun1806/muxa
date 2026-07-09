import AppKit
import SwiftUI

/// 워크스페이스 하위 프로젝트 탭바(상단). 각 프로젝트 = 독립 분할 레이아웃(Bonsplit) 하나.
/// 크롬식 탭 — 클릭 전환, ✕ 닫기(마지막 하나는 유지), + 로 새 프로젝트/워크트리 추가.
struct ProjectTabBar: View {
    let state: AppState
    let workspace: Workspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(workspace.projects) { project in
                    tab(project)
                }
                addButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 34)
        .background(Color.pPanel)
    }

    @ViewBuilder
    private func tab(_ project: Project) -> some View {
        let active = project.id == workspace.activeProjectId
        HStack(spacing: 6) {
            Image(systemName: project.path == nil ? "folder" : "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
            Text(project.name)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            if workspace.projects.count > 1 {
                Button {
                    state.closeProject(project.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.pMuted)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(active ? Color.pBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color.pBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { state.setActiveProject(project.id) }
        .help(project.path.map { displayPath($0, home: SystemPaths.home) } ?? "워크스페이스 폴더")
    }

    private var addButton: some View {
        Menu {
            Button {
                state.addProject(name: "프로젝트 \(workspace.projects.count + 1)", path: nil)
            } label: {
                Label("새 프로젝트 (같은 폴더)", systemImage: "plus.square")
            }
            Button {
                pickFolder()
            } label: {
                Label("폴더 / 워크트리 선택…", systemImage: "arrow.triangle.branch")
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Color.pMuted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
        .help("새 프로젝트")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspace.path.map { URL(fileURLWithPath: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            state.addProject(name: basename(url.path), path: url.path)
        }
    }
}
