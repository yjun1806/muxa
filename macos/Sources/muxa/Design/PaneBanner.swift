import SwiftUI

/// 칸(pane) 상단에 얹히는 배너들의 공통 크롬 — 세션 재개(§ResumeOverlay)·닫기 확인(§CloseConfirmOverlay)이 공유한다.
/// 같은 컨테이너·CTA 모양을 배너마다 복붙하지 않도록 한 곳에 둔다(Design/PanelChrome과 같은 취지).
extension View {
    /// 배너 컨테이너 — 반투명 배경 + 경계 + 폭 제한. 칸 위에 겹쳐도 아래 터미널이 비쳐 위치를 잃지 않는다.
    func paneBannerChrome(maxWidth: CGFloat) -> some View {
        self
            .padding(.horizontal, Space.panelInset)
            .padding(.vertical, Space.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.pBorder, lineWidth: RowHeight.hairline))
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, Space.lg)
    }

    /// 1급 CTA 라벨 스타일 — brand 캡슐. 텍스트 등급(4.5:1) 토큰(pBrand+pOnBrand)이라 양 모드 AA 통과.
    /// 비텍스트(3:1) 등급 색에 흰 글자를 얹으면 다크에서 AA에 미달하므로 이 조합을 고정한다.
    func paneBannerCTA() -> some View {
        self
            .padding(.horizontal, Space.panelInset)
            .padding(.vertical, 5)
            .background(Color.pBrand)
            .foregroundStyle(Color.pOnBrand)
            .clipShape(Capsule())
    }

    /// 배너 등장/퇴장 — 위에서 슬라이드 + 페이드. 배너 뷰에 건다.
    /// 실제 애니메이션은 조건이 바뀌는 부모(ZStack)에 `.animation(Motion.medium, value:)`로 건다 —
    /// transition은 삽입/제거될 뷰에, 애니메이션 컨텍스트는 그 뷰를 넣고 빼는 컨테이너에 있어야 발동한다.
    func paneBannerTransition() -> some View {
        transition(.move(edge: .top).combined(with: .opacity))
    }
}
