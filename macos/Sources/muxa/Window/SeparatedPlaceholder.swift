import SwiftUI

/// 메인 창에서 "이 프로젝트는 다른 창에 있다"를 말하는 카드.
///
/// **숨기지 않는다.** 사이드바는 분리된 프로젝트도 그대로 보여주므로, 클릭했을 때 아무것도 안 나오면
/// 사용자는 프로젝트를 잃었다고 느낀다. 여기서 그 창을 앞으로 부르거나 되돌릴 수 있어야
/// 분리 창을 잃어버려도 프로젝트가 도달 불가가 되지 않는다.
struct SeparatedPlaceholder: View {
    let state: AppState
    let project: Project

    var body: some View {
        EmptyState(icon: "macwindow", title: "\(project.name) — 다른 창에서 열려 있습니다") {
            HStack(spacing: Space.md) {
                action("그 창 보기", icon: "arrow.up.forward.app") {
                    state.focusWindow(owning: project.id)
                }
                action("이 창으로 되돌리기", icon: "macwindow.badge.minus") {
                    state.moveProjects([project.id], to: .main)
                }
            }
        }
        .background(Color.pBg)
    }

    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon)
                .font(.muxa(.body))
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(Color.pBtnHover, in: RoundedRectangle(cornerRadius: Radius.md))
                .foregroundStyle(Color.pFg)
        }
        .buttonStyle(.plain)
        .clickCursor()
    }
}
