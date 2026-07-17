import SwiftUI

/// 목록 행 채움 문법(L1) — hover는 옅게(`btnHover`), 선택(지금 보고 있는 탭)은 활성 채움(`btnActive`).
/// 행마다 자기 hover 상태를 가진다(행 재활용에도 안전 — 로컬 @State).
///
/// 사이드바 에이전트 목록·주의 큐 카드 행이 공유한다 — "클릭 가능한 목록 행"은 어디서든 같은 문법.
struct ListRowFill: ViewModifier {
    var selected = false
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(selected ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .onHover { hovered = $0 }
    }
}
