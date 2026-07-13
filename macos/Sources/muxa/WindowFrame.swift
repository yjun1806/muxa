import AppKit

/// 창 프레임 복원 판정(순수) — 부작용 없음.
enum WindowFrame {
    /// 타이틀바로 인정하는 상단 띠 높이.
    private static let titleBarHeight: CGFloat = 28
    /// 드래그로 창을 되찾으려면 이만큼은 잡을 폭이 화면 안에 있어야 한다.
    private static let minGrabWidth: CGFloat = 80

    /// 이 프레임의 창을 사용자가 **잡을 수 있는가**.
    ///
    /// 본문이 조금 걸치는 것으로는 부족하다 — 타이틀바를 붙잡을 수 없으면 창을 화면 안으로
    /// 되돌릴 방법이 없다. 외장 모니터를 뽑으면 저장된 좌표는 언제든 화면 밖이 되므로,
    /// 복원 직후 이 검사를 통과하지 못하면 기본 크기로 가운데에 다시 띄운다.
    static func isReachable(_ frame: NSRect, screens: [NSRect]) -> Bool {
        let titleBar = NSRect(x: frame.minX,
                              y: frame.maxY - titleBarHeight,
                              width: frame.width,
                              height: titleBarHeight)
        return screens.contains { screen in
            let visible = screen.intersection(titleBar)
            return !visible.isNull && visible.width >= minGrabWidth && visible.height > 0
        }
    }
}
