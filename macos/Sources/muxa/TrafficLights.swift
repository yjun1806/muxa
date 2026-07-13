import AppKit

/// 신호등(닫기·최소화·확대) 세로 정렬.
///
/// `fullSizeContentView` + 투명 타이틀바에서 신호등은 표준 타이틀바(약 28pt) 안에 놓인다.
/// 우리 상단바는 그보다 높아서(`RowHeight.topBar`) 그대로 두면 신호등만 위에 붙는다.
///
/// **버튼을 개별로 옮기지 않는다.** 버튼의 y를 바꾸면 컨테이너(타이틀바 뷰)가 그대로라 잘리거나
/// 오히려 위로 밀린다. 대신 **컨테이너 자체를 아래로 내려** 타이틀바 전체가 상단바 중앙에 놓이게 한다.
///
/// 목표 위치를 절대값으로 계산하므로 여러 번 불려도 누적되지 않는다(시스템이 레이아웃을 되돌릴 때마다
/// 다시 부르면 된다 — `AppDelegate`의 창 델리게이트가 호출).
enum TrafficLights {
    /// 창 왼쪽 가장자리에서 첫 버튼까지의 여백(기본값보다 넉넉하게 — 상단바가 커진 만큼 좌우도 벌린다).
    private static let leadingInset: CGFloat = 14

    static func align(in window: NSWindow, barHeight: CGFloat) {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { window.standardWindowButton($0) }
        guard let close = buttons.first,
              let titlebar = close.superview,
              let frame = titlebar.superview else { return }

        // 세로: 타이틀바 전체를 내려 상단바의 중앙에 앉힌다.
        // 프레임 뷰는 non-flipped(원점이 아래) — 타이틀바의 기본 y는 "창 높이 - 타이틀바 높이"(=맨 위).
        let titlebarHeight = titlebar.frame.height
        let inset = (barHeight - titlebarHeight) / 2
        if inset > 0 {
            let targetY = frame.bounds.height - titlebarHeight - inset
            titlebar.setFrameOrigin(NSPoint(x: titlebar.frame.origin.x, y: targetY))
        }

        // 가로: 버튼 간격은 그대로 두고 시작점만 민다. 절대 위치로 계산해 여러 번 불려도 누적되지 않는다.
        let spacing = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
        for (index, button) in buttons.enumerated() {
            let x = leadingInset + spacing * CGFloat(index)
            button.setFrameOrigin(NSPoint(x: x, y: button.frame.origin.y))
        }
    }
}
