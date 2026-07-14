import SwiftUI

/// 분리 창 상단바의 프로젝트 스트립 — 그 창이 **여러 프로젝트를 품었을 때** 안에서 전환하는 유일한 경로.
///
/// 분리 창엔 사이드바가 없다(DESIGN 5 — 트리가 둘이면 어느 쪽이 진짜인지 매번 고민하게 된다).
/// 그런데 워크스페이스를 통째로 분리하면 그 창은 `activeProjectId` 하나만 그리므로, 전환 수단이 없으면
/// **두 번째 이후 프로젝트가 어느 창에도 안 보인다**(메인은 소유권 가드로 안 그린다).
/// 그래서 사이드바 대신 이 스트립이 그 창의 프로젝트만 세운다 — 탐색이 아니라 창 지역 전환이다.
///
/// 프로젝트가 하나뿐이면 그리지 않는다(브레드크럼이 이미 그 이름을 말한다).
struct WindowProjectStrip: View {
    let state: AppState
    let window: ProjectWindow

    var body: some View {
        if window.projectIds.count > 1 {
            HStack(spacing: Space.xs) {
                ForEach(window.projectIds, id: \.self) { projectId in
                    if let project = state.located(projectId)?.project {
                        pill(project, active: projectId == window.activeProjectId)
                    }
                }
            }
        }
    }

    /// 사이드바 행과 **같은 신호 문법**(상태 점 + 이름) — 색·크기는 `ProjectStatusStyle` 하나에서 온다.
    private func pill(_ project: Project, active: Bool) -> some View {
        let status = state.projectStatus(project.id)
        return Button {
            state.setActiveProject(project.id, inWindow: window.id)
        } label: {
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(ProjectStatusStyle.color(status))
                    .frame(width: ProjectStatusStyle.dotSize(status),
                           height: ProjectStatusStyle.dotSize(status))
                    .frame(width: IconSize.statusSlot)
                Text(project.name)
                    .font(project.path == nil ? .muxa(.label, weight: active ? .semibold : .regular)
                                              : .muxaMono(.label, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.pFg : Color.pMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.md)
            .frame(height: IconSize.control)
            .background(active ? Color.pBtnActive.opacity(0.6) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(project.name)
    }
}
