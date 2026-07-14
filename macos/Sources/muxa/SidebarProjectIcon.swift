import SwiftUI

/// 접힌 모드(icon 52 · slim 14)의 **프로젝트** 항목 — 이름이 없으니 상태 점 하나가 전부다.
///
/// 여기가 없으면 접힌 모드에서 프로젝트에 마우스로 닿을 방법이 사라진다(전환·닫기·이름 변경 전부).
/// 예전엔 상단바 프로젝트 탭이 사이드바 모드와 무관하게 그 역할을 했지만, 프로젝트 전환의 유일한
/// 경로가 사이드바가 된 이상 **모든 모드의 사이드바가** 그 경로를 제공해야 한다.
/// (펼침 규칙은 확장 트리와 같다 — `SidebarTree.isExpanded`. 활성 워크스페이스는 항상 펼쳐진다.)
struct SidebarProjectIcon: View {
    let state: AppState
    let workspace: Workspace
    let project: Project
    let sidebarWidth: CGFloat
    let showsNameChip: Bool
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?

    private var active: Bool { project.id == workspace.activeProjectId && workspace.id == state.activeId }

    var body: some View {
        let status = state.projectStatus(project.id)
        Button(action: select) {
            Circle()
                .fill(ProjectStatusStyle.color(status))
                .frame(width: ProjectStatusStyle.dotSize(status), height: ProjectStatusStyle.dotSize(status))
                .frame(maxWidth: .infinity)
                // 워크스페이스 항목(row 24)보다 얕게 — 자식이라는 걸 크기로 말한다(들여쓸 폭이 없다).
                .frame(height: RowHeight.tight)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        // 점 하나가 전부인 항목 — 라벨이 없으면 VO엔 이름 없는 버튼이다.
        .sidebarRow(id: project.id, label: project.name, selected: active,
                    hoveredId: $hoveredId, menuOpenId: $menuOpenId) {
            ProjectMenu.items(for: project, in: workspace, state: state)
        }
        .overlay(alignment: .leading) {
            if hoveredId == project.id, menuOpenId == nil, showsNameChip {
                SidebarNameChip(title: project.name,
                                subtitle: displayPath(project.path ?? workspace.path, home: SystemPaths.home),
                                mono: project.usesMonoName)
                    .offset(x: Sidebar.chipOffset(width: sidebarWidth))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    /// 선택은 **중립 채움**(브랜드 wash 금지) — 확장 트리의 프로젝트 행과 같은 언어다.
    private var background: Color {
        if active { return .pBtnActive }
        return hoveredId == project.id || menuOpenId == project.id ? .pBtnHover : .clear
    }

    /// 확장 트리의 프로젝트 행과 같은 동작 — 배지가 있으면 Git 패널까지 함께 연다.
    /// `setActiveId`를 **먼저** 부른다(setActiveProject는 활성 워크스페이스 대상이라 조용히 씹힌다).
    private func select() {
        if state.badgedProjects.contains(project.id) {
            state.revealActivity(projectId: project.id)
        } else {
            state.setActiveId(workspace.id)
            state.setActiveProject(project.id)
        }
    }
}
