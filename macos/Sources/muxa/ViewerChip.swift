import SwiftUI

/// 사이드바 프로젝트 펼침 목록의 **뷰어 칩** — 문서·HTML·코드·미디어·변경 같은 "가만히 있는 파일 탭"을
/// 풀폭 행 대신 아이콘+종류+개수 알약으로 압축한다(터미널은 여전히 행이다 — 상태가 변하니 지켜봐야 한다).
///
/// **표현 전용이다**: 클릭 동작·툴팁·접근성 라벨은 호출부(`SidebarProjectRow`)가 붙인다(행과 같은 문법).
/// 선택(지금 보고 있는 탭)은 목록 규약대로 **중립 채움**(btnActive) — 색은 상태에만(Palette 원칙).
/// 상시 면은 `CountBadge`와 같은 옅은 토큰면(btnHover), hover는 테두리를 진하게 해 눌림을 드러낸다.
struct ViewerChip: View {
    /// 종류 아이콘(SF Symbol) — `AgentRow.typeIcon`.
    let icon: String
    /// 종류 이름("HTML"·"문서"·"코드"…) — `AgentRow.title`(뷰어는 종류가 곧 이름).
    let title: String
    /// 안에 열린 서브탭 개수. nil이면 숨긴다(0은 소음).
    let count: Int?
    /// 지금 보고 있는 탭인가.
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                // 종류 아이콘 — 무채 슬롯 고정(터미널 행 `typeMark`와 같은 규칙: WHO/무엇을 상태와 분리).
                Image(systemName: icon)
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
                Text(title)
                    .font(.muxa(.label))
                    .foregroundStyle(selected || hovered ? Color.pFg : Color.pMuted)
                if let count {
                    Text("\(count)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.tight)
            .background(fill, in: Capsule())
            .overlay { Capsule().strokeBorder(border, lineWidth: RowHeight.hairline) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
    }

    /// 채움 — 선택=활성 채움(btnActive), 아니면 옅은 토큰면(btnHover). 색은 안 쓴다(선택은 중립이 규약).
    private var fill: Color { selected ? Color.pBtnActive : Color.pBtnHover }

    /// 테두리 — hover에서 진해져 "누를 수 있음"을 드러낸다(선택은 이미 채움이 말한다).
    private var border: Color { hovered ? Color.pMuted : Color.pBorder }
}
