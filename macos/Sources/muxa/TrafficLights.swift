import AppKit

/// 신호등(닫기·최소화·확대) 세로 정렬.
///
/// `fullSizeContentView` + 투명 타이틀바에서 신호등은 표준 타이틀바(약 28pt) 안에 놓인다.
/// 우리 상단바는 그보다 높아서(`RowHeight.topBar`) 그대로 두면 신호등만 위에 붙는다.
///
/// **버튼을 개별로 옮기지 않는다.** 버튼의 y를 바꾸면 컨테이너(타이틀바 뷰)가 그대로라 잘리거나
/// 오히려 위로 밀린다. 대신 **컨테이너 자체를 아래로 내려** 타이틀바 전체가 상단바 중앙에 놓이게 한다.
///
/// 시스템은 창이 키를 잃거나 다시 얻을 때, 전체화면·리사이즈 때 타이틀바를 제 위치(맨 위)로 되돌린다.
/// 창 이벤트를 하나씩 쫓아다니면 반드시 빠지는 경우가 생기므로(예: 비활성 창의 신호등만 5pt 위로 튐)
/// **타이틀바 뷰의 프레임 변화를 직접 감시해** 되돌려질 때마다 다시 내린다.
/// 목표 위치는 절대값이라 여러 번 불려도 누적되지 않고, 이미 제자리면 아무것도 하지 않는다(알림 루프 없음).
@MainActor
enum TrafficLights {
    /// 창 왼쪽 가장자리에서 첫 버튼까지의 여백(기본값보다 넉넉하게 — 상단바가 커진 만큼 좌우도 벌린다).
    private static let leadingInset: CGFloat = 14
    /// 신호등 버튼 간격·너비의 표준값(실제 spacing은 런타임에 버튼에서 읽지만, 예약 폭 계산엔 표준값을 쓴다).
    private static let nominalSpacing: CGFloat = 20
    private static let nominalButtonWidth: CGFloat = 14
    /// 마지막 버튼과 상단바 콘텐츠(워드마크) 사이 최소 꼬리 여백.
    private static let trailingGap: CGFloat = 8

    /// 상단바 좌측에서 신호등 3개가 차지하는 폭 — 상단바 콘텐츠(워드마크)가 이만큼 시작점을 민다.
    /// **`leadingInset`과 같은 출처를 쓴다.** 예전엔 ContentView에 `76`이 하드코딩돼 신호등 기하와 몰래
    /// 커플링돼 있었다(여백을 벌리면 워드마크가 버튼을 덮었다). 여기서 한 번 계산해 노출한다.
    static let reservedLeadingWidth: CGFloat =
        leadingInset + nominalSpacing * 2 + nominalButtonWidth + trailingGap

    /// 이미 감시 중인 타이틀바 뷰 — 옵저버 중복 등록 방지.
    /// **약한 참조**여야 한다: 창이 닫히면 항목이 저절로 빠진다. 주소(ObjectIdentifier)로 들고 있으면
    /// 죽은 뷰의 주소가 남고, 새 창의 타이틀바가 같은 주소에 잡히면 "이미 감시 중"으로 오판해
    /// 그 창만 자가복구를 못 받는다(멀티 윈도우에서 재현되는 유령 버그).
    private static let observed = NSHashTable<NSView>.weakObjects()

    static func align(in window: NSWindow, barHeight: CGFloat) {
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        apply(titlebar: titlebar, barHeight: barHeight)
        watch(titlebar, barHeight: barHeight)
    }

    private static func apply(titlebar: NSView, barHeight: CGFloat) {
        guard let frame = titlebar.superview else { return }
        // 전체화면에선 시스템이 타이틀바를 애니메이션으로 내렸다 올린다(hover reveal) — 거기 끼어들면
        // 매 프레임 스냅백이 걸려 신호등이 떨린다. 그땐 시스템 배치를 그대로 둔다(상단바도 안 겹친다).
        guard let window = titlebar.window, !window.styleMask.contains(.fullScreen) else { return }

        // 세로: 타이틀바 전체를 내려 상단바의 중앙에 앉힌다.
        // 프레임 뷰는 non-flipped(원점이 아래) — 타이틀바의 기본 y는 "창 높이 - 타이틀바 높이"(=맨 위).
        let titlebarHeight = titlebar.frame.height
        let inset = (barHeight - titlebarHeight) / 2
        if inset > 0 {
            let targetY = frame.bounds.height - titlebarHeight - inset
            if abs(titlebar.frame.origin.y - targetY) > 0.5 {
                titlebar.setFrameOrigin(NSPoint(x: titlebar.frame.origin.x, y: targetY))
            }
        }

        // 가로: 버튼 간격은 그대로 두고 시작점만 민다. 절대 위치로 계산해 여러 번 불려도 누적되지 않는다.
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { window.standardWindowButton($0) }
        let spacing = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
        for (index, button) in buttons.enumerated() {
            let x = leadingInset + spacing * CGFloat(index)
            if abs(button.frame.origin.x - x) > 0.5 {
                button.setFrameOrigin(NSPoint(x: x, y: button.frame.origin.y))
            }
        }
    }

    /// 시스템이 타이틀바를 되돌리면(프레임 변경) 즉시 다시 내린다.
    ///
    /// 재진입 주의: `queue: .main`은 이미 메인 스레드에서 포스팅되면 **동기 실행**될 수 있어
    /// `setFrameOrigin` → 알림 → `apply`로 되돌아온다. 무한루프를 막는 건 `apply`의 0.5pt 가드뿐이다
    /// (제자리면 프레임을 안 건드리니 알림도 안 나간다) — 그 가드를 지우면 루프가 돈다.
    private static func watch(_ titlebar: NSView, barHeight: CGFloat) {
        guard !observed.contains(titlebar) else { return }
        observed.add(titlebar)

        // NSView 기본값이 true지만, 알림을 못 받으면 이 파일 전체가 무력해지는 전제라 명시해 둔다.
        titlebar.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: titlebar, queue: .main
        ) { [weak titlebar] _ in
            MainActor.assumeIsolated {
                guard let titlebar else { return }
                apply(titlebar: titlebar, barHeight: barHeight)
            }
        }
    }
}
