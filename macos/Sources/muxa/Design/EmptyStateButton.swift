import SwiftUI

/// `EmptyState` 액션 슬롯의 표준 버튼 — 크기·모양을 여기서만 정한다(EmptyState의 아이콘·제목 계약과 같은 취지).
/// 호출부(빈 프로젝트 뷰·워크트리 링크 탭)가 각자 조판하면 세 번째 호출부부터 드리프트한다.
///
/// `prominent` = 1급 CTA(브랜드 채움) — **화면당 하나만**(DESIGN 2: brand는 1급 CTA·강조에만, 크롬 예산 1% 미만).
/// 기본은 중립 채움(`btnHover`) — 색은 신호에 아낀다.
struct EmptyStateButton: View {
    let title: String
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.muxa(.title))
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(prominent ? Color.pBrand : Color.pBtnHover,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .foregroundStyle(prominent ? Color.pOnBrand : Color.pFg) // pBrand+pOnBrand = 양 모드 AA(PaneBanner CTA와 동일 근거)
        }
        .buttonStyle(.plain)
        .clickCursor()
    }
}
