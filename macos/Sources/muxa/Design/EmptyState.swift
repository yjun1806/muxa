import SwiftUI

/// 빈 상태 — 보여줄 게 없을 때의 화면("터미널이 없습니다"·"놓친 알림 없음").
/// 아이콘·제목 크기는 본문 스케일 밖의 장식이라 여기 안에만 둔다(다른 곳에서 이 크기를 쓰지 않는다).
///
/// `compact`는 팝오버처럼 좁은 곳용 — 메인 영역을 채우는 빈 상태보다 작게 그린다.
struct EmptyState<Action: View>: View {
    let icon: String
    let title: String
    var compact = false
    @ViewBuilder let action: () -> Action

    private var iconSize: CGFloat { compact ? 22 : 34 }
    private var titleFont: Font { compact ? .muxa(.body) : .system(size: 15, weight: .medium) }

    var body: some View {
        VStack(spacing: compact ? Space.sm : Space.lg) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(compact ? Color.pMuted.opacity(0.6) : Color.pMuted)
            Text(title)
                .font(titleFont)
                .foregroundStyle(compact ? Color.pMuted : Color.pFg)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Action == EmptyView {
    /// 액션 버튼이 없는 빈 상태.
    init(icon: String, title: String, compact: Bool = false) {
        self.init(icon: icon, title: title, compact: compact) { EmptyView() }
    }
}
