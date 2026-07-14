import SwiftUI

/// 직접 그린 **행**을 접근성(VoiceOver) 요소로 만드는 공용 모디파이어.
///
/// muxa의 조작면은 대부분 `Button`이 아니라 `contentShape(Rectangle()) + onTapGesture`다 —
/// 그렇게 그리면 SwiftUI가 접근성 요소로 노출하지 않아 **VO 커서가 아예 착지하지 못하고**,
/// 읽을 라벨도 활성화할 액션도 없다. 아이콘만 있는 행은 SF Symbol 기본 설명("plus"·"circle")으로 읽힌다.
///
/// 사이드바 행(4종)·주의 큐 헤더·그룹 서브탭·⌘K 팔레트 행이 전부 같은 모양이라 여기 한 곳에 모은다.
extension View {
    /// - label: VO가 읽을 이름.
    /// - selected: 지금 선택된 행인가(색은 스크린리더에 존재하지 않는다 — 트레이트로 말해야 한다).
    /// - activate: 행 클릭과 같은 동작. nil이면 이 뷰가 이미 `Button`이라는 뜻 —
    ///   요소로 묶지 않고 라벨·선택 상태만 얹는다(버튼의 액션·트레이트를 덮어쓰지 않게).
    func accessibilityRow(label: String,
                          selected: Bool = false,
                          activate: (() -> Void)? = nil) -> some View {
        modifier(AccessibleRow(label: label, selected: selected, activate: activate))
    }
}

private struct AccessibleRow: ViewModifier {
    let label: String
    let selected: Bool
    let activate: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let activate {
            // `.combine`이면 행 안의 버튼(닫기·추가)은 사라지지 않고 이 요소의 **보조 액션**으로 남는다.
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
                .accessibilityAction { activate() }
        } else {
            content
                .accessibilityLabel(label)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}
