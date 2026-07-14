import SwiftUI

/// 프로젝트 행 = 트리의 **주인공**. 폴더가 아니라 "그 안의 에이전트가 지금 뭘 하고 있나"를 말한다.
///
/// 선택 표시는 브랜드색 wash가 아니라 **중립 채움**(btnActive) — 크롬은 무채, 색은 신호다.
/// 워크트리 프로젝트(path != nil)의 이름은 모노스페이스다(브랜치는 식별자다).
struct SidebarProjectRow: View {
    let state: AppState
    let workspace: Workspace
    let project: Project
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?

    private var active: Bool { project.id == workspace.activeProjectId && workspace.id == state.activeId }
    private var hovered: Bool { hoveredId == project.id || menuOpenId == project.id }

    var body: some View {
        let status = state.projectStatus(project.id)
        let services = state.services(of: project.id)
        HStack(spacing: Space.sm) {
            // 슬롯은 항상 12pt — 점 크기가 바뀌어도(유휴 5 / 신호 6) 이름이 흔들리지 않는다.
            Circle()
                .fill(ProjectStatusStyle.color(status))
                .frame(width: ProjectStatusStyle.dotSize(status), height: ProjectStatusStyle.dotSize(status))
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
            Text(project.name)
                .font(nameFont)
                .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.xs)
            // ✕는 서비스 요약과 **같은 자리**를 쓴다(hover 시 교체 → 행 폭이 흔들리지 않는다).
            if hovered {
                if workspace.projects.count > 1 { closeButton }
            } else if !services.isEmpty {
                serviceSummary(services)
            }
        }
        .padding(.leading, Space.treeIndent) // 2단 트리의 들여쓰기 = 위계
        .padding(.trailing, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RowHeight.row)
        .background(active ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        .onTapGesture {
            // 배지(주의) 있는 프로젝트로 이동하면 Git 패널까지 함께 연다(원클릭 검토 동선).
            if state.badgedProjects.contains(project.id) {
                state.revealActivity(projectId: project.id)
            } else {
                // **setActiveId 먼저** — setActiveProject는 활성 워크스페이스 대상이라,
                // 다른 그룹의 프로젝트를 눌렀을 때 전환 없이 부르면 조용히 씹힌다.
                state.setActiveId(workspace.id)
                state.setActiveProject(project.id)
            }
        }
        .sidebarRow(id: project.id, hoveredId: $hoveredId, menuOpenId: $menuOpenId) {
            ProjectMenu.items(for: project, in: workspace, state: state)
        }
        .help(displayPath(project.path ?? workspace.path, home: SystemPaths.home))
    }

    /// 자체 경로를 가진 프로젝트(워크트리·임의 폴더)의 이름은 식별자라 모노스페이스로 읽는다
    /// (판정은 `Project.usesMonoName` 한 곳 — 브레드크럼·이름 칩도 같은 규칙을 쓴다).
    private var nameFont: Font {
        let weight: Font.Weight = active ? .medium : .regular
        return project.usesMonoName ? .muxaMono(.body, weight: weight) : .muxa(.body, weight: weight)
    }

    /// 서비스 요약 — 색·글리프 규칙은 `ServiceStatusStyle` 재사용(새 규칙을 만들지 않는다).
    private func serviceSummary(_ services: [Service]) -> some View {
        let summary = ServiceStatusStyle.summarize(state.serviceStatuses(of: project.id))
        return HStack(spacing: Space.tight) {
            Image(systemName: ServiceStatusStyle.glyph(summary)).font(.muxa(.micro))
            Text("\(services.count)").font(.muxaMono(.caption))
        }
        .foregroundStyle(ServiceStatusStyle.color(summary))
    }

    private var closeButton: some View {
        Button { state.closeProject(project.id) } label: {
            Image(systemName: "xmark")
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("프로젝트 닫기")
    }
}
