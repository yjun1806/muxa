import SwiftUI

/// 패널(사이드바·git·탐색기) 공통 크롬 조각 — 구분선·행·바·라벨.
/// 같은 모양을 화면마다 다시 조립하지 않도록 여기 한 곳에 둔다.

/// 가로 구분선 — 1px, 경계색. (기존엔 `Rectangle().fill(...).frame(height: 1)`이 20곳에 복붙돼 있었다.)
struct HDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.pBorder)
            .frame(height: RowHeight.hairline)
    }
}

/// 패널 안의 보조 텍스트 — 빈 상태 메시지("변경 없음")·설명.
struct PanelLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.muxa(.label))
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.panelInset)
            .padding(.vertical, Space.md)
    }
}

/// 섹션 제목 + 개수 — 목록을 나누는 얕은 헤더("스테이지됨 3").
struct SectionLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(title)
                .font(.muxa(.caption, weight: .semibold))
                .foregroundStyle(Color.pMuted)
            if let count {
                Text("\(count)")
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted.opacity(0.7))
            }
        }
    }
}

extension View {
    /// 목록 한 행 — 가로 인셋 + hover 배경. `height`가 nil이면 내용 높이를 따른다(여러 줄 행).
    /// hover 피드백을 행 단위로 통일해 "어디를 누르는지"가 항상 보이게 한다.
    func panelRow(height: CGFloat? = RowHeight.row) -> some View {
        modifier(PanelRowStyle(height: height))
    }

    /// 도구줄·헤더 — 가로 인셋 + 고정 높이(hover 없음).
    func panelBar(height: CGFloat = RowHeight.toolbar) -> some View {
        padding(.horizontal, Space.panelInset)
            .frame(height: height)
    }
}

/// `panelRow`의 실제 구현 — hover 상태를 자기 안에 가둔다(상위 뷰가 hover를 몰라도 된다).
private struct PanelRowStyle: ViewModifier {
    let height: CGFloat?
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Space.panelInset)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Color.pBtnHover : .clear)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(Motion.fast, value: hovered)
    }
}
