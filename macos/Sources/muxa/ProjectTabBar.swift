import AppKit
import SwiftUI

/// 워크스페이스 하위 프로젝트 탭 묶음 — 상단바 한 줄에 임베드된다(별도 줄 아님).
/// 각 프로젝트 = 독립 분할 레이아웃(Bonsplit) 하나. 크롬식 탭 — 클릭 전환,
/// ✕ 닫기(마지막 하나는 유지), + 로 새 프로젝트/워크트리 추가.
struct ProjectTabBar: View {
    let state: AppState
    let workspace: Workspace

    @State private var showWorktreePicker = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(workspace.projects) { project in
                tab(project)
            }
            addButton
        }
        .fixedSize(horizontal: true, vertical: false)
        .sheet(isPresented: $showWorktreePicker) {
            WorktreePicker(dir: workspace.path ?? SystemPaths.currentDir ?? SystemPaths.home) { name, path in
                state.addProject(name: name, path: path)
                showWorktreePicker = false
            } onCancel: {
                showWorktreePicker = false
            }
        }
    }

    @ViewBuilder
    private func tab(_ project: Project) -> some View {
        let active = project.id == workspace.activeProjectId
        HStack(spacing: 6) {
            Image(systemName: project.path == nil ? "folder" : "arrow.triangle.branch")
                .font(.muxa(.label))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
            Text(project.name)
                .font(.muxa(.body, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            if !active, state.badgedProjects.contains(project.id) {
                // 백그라운드 활동(에이전트 끝남·벨·알림) — 이 프로젝트를 안 보는 동안 쌓임.
                Circle().fill(Color.pBorderFocus).frame(width: 6, height: 6)
            }
            if workspace.projects.count > 1 {
                Button {
                    state.closeProject(project.id)
                } label: {
                    Image(systemName: "xmark").font(.muxa(.micro, weight: .semibold))
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
        .onTapGesture {
            // 배지(●) 있는 프로젝트로 이동하면 자동으로 Git 패널까지 연다(원클릭 검토 동선).
            // 배지 없는 일반 전환은 패널을 강제로 열지 않는다.
            if state.badgedProjects.contains(project.id) {
                state.revealActivity(projectId: project.id)
            } else {
                state.setActiveProject(project.id)
            }
        }
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
                showWorktreePicker = true
            } label: {
                Label("워크트리…", systemImage: "arrow.triangle.branch")
            }
            Button {
                pickFolder()
            } label: {
                Label("임의 폴더 선택…", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus").font(.muxa(.body)).foregroundStyle(Color.pMuted)
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
