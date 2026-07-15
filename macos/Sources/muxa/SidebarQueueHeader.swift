import SwiftUI

/// 주의 큐 한 줄 — 트리 맨 위. **기다리는 세션이 하나도 없으면 아예 렌더하지 않는다**
/// (빈 상태를 위한 빈 줄은 크롬 소음이다).
///
/// 테두리·틴트 박스를 두르지 않는다 — 색은 점 하나가 다 말한다(hover 배경만).
struct SidebarQueueHeader: View {
    let state: AppState
    @State private var hovered = false

    var body: some View {
        if let target = state.nextWaiting {
            HStack(spacing: Space.sm) {
                // 주의 신호도 사이드바 행과 같은 어휘(StatusStyle) — 생 색·점 대신 attention 글리프.
                Image(systemName: StatusStyle.glyph(.attention))
                    .font(.muxa(.caption, weight: .semibold))
                    .foregroundStyle(StatusStyle.color(.attention))
                    .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                Text(text(target))
                    .font(.muxa(.body))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Space.xs)
                Text("⌘⇧A")
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.row)
            .background(hovered ? Color.pBtnHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
            .clickCursor()
            .onTapGesture { state.jumpToNextWaiting() }
            .accessibilityRow(label: text(target), activate: { state.jumpToNextWaiting() })
            .onHover { hovered = $0 }
            .animation(Motion.fast, value: hovered)
        }
    }

    /// **여럿이면 이름을 못 박지 않는다** — ⌘⇧A(jumpToNextWaiting)는 현재 커서 다음 대기 세션으로
    /// 순환 점프하므로, 목록의 첫 이름을 말하면 클릭했을 때 다른 곳으로 튀어 거짓말이 된다.
    ///
    /// 단위는 **프로젝트**다(`badgedProjects` = 이 헤더가 뜨는 근거). 한 프로젝트 안에 대기 탭이
    /// 여럿일 수 있으므로 "세션"이라고 말하면 숫자가 실제 대기 세션 수와 어긋난다.
    private func text(_ target: SidebarTree.WaitingRef) -> String {
        let count = state.badgedProjects.count
        return count <= 1 ? "\(target.projectName) 가 입력을 기다립니다"
                          : "\(count)개 프로젝트가 입력을 기다립니다"
    }
}
