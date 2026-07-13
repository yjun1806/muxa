import AppKit
import SwiftUI

/// 워크스페이스 하위 프로젝트 탭 묶음 — 상단바 한 줄에 임베드된다(별도 줄 아님).
/// 각 프로젝트 = 독립 분할 레이아웃(Bonsplit) 하나. 크롬식 탭 — 클릭 전환,
/// ✕ 닫기(마지막 하나는 유지), + 로 새 프로젝트/워크트리 추가.
struct ProjectTabBar: View {
    let state: AppState
    let workspace: Workspace

    @State private var showWorktreePicker = false
    /// 지금 마우스가 올라간 탭 — 닫기 버튼·배경 강조 대상.
    @State private var hoveredId: String?

    var body: some View {
        HStack(spacing: Space.xs) {
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

    /// 프로젝트 탭 — 활성 탭은 콘텐츠와 같은 판(흰 배경 + 테두리)이 되어 "이 탭이 아래 화면"임을 잇는다.
    /// 비활성은 배경 없이 글자만, hover하면 옅게 떠오른다.
    @ViewBuilder
    private func tab(_ project: Project) -> some View {
        let active = project.id == workspace.activeProjectId
        let hovered = hoveredId == project.id
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: project.path == nil ? "folder" : "arrow.triangle.branch")
                .font(.muxa(.label))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
            Text(project.name)
                .font(.muxa(.body, weight: active ? .medium : .regular))
                .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            if !active, state.badgedProjects.contains(project.id) {
                // 백그라운드 활동(에이전트 끝남·벨·알림) — 이 프로젝트를 안 보는 동안 쌓임.
                Circle().fill(Color.pBorderFocus).frame(width: 6, height: 6)
            }
            if workspace.projects.count > 1, active || hovered {
                // 닫기는 활성·hover일 때만 — 비활성 탭마다 ✕가 떠 있으면 탭바가 산만하다.
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
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.tab)
        .background(tabBackground(active: active, hovered: hovered))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredId = project.id } else if hoveredId == project.id { hoveredId = nil }
        }
        // 우클릭 → 프로젝트 메뉴(이름·터미널·경로·닫기). 좌클릭 전환은 그대로.
        .onRightClick { point in
            MuxaMenuWindow.shared.show(
                ProjectMenu.items(for: project, in: workspace, state: state), at: point)
        }
        .animation(Motion.fast, value: hovered)
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

    /// 탭 배경 — 활성은 콘텐츠와 같은 판(테두리로 마감), 비활성은 hover에만 옅게.
    @ViewBuilder
    private func tabBackground(active: Bool, hovered: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.pBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.pBorder, lineWidth: 1)
                )
        } else if hovered {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.pBtnHover.opacity(0.5))
        }
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
        .frame(width: RowHeight.tab, height: RowHeight.tab)
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
