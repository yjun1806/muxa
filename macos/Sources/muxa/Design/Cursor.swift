import AppKit
import SwiftUI

/// 클릭 가능한 크롬 요소의 **커서 피드백**.
///
/// SwiftUI 버튼은 macOS에서 커서를 바꾸지 않는다 — 네이티브 컨트롤(NSButton)의 관례가 그렇기 때문이다.
/// 하지만 muxa의 크롬은 네이티브 컨트롤이 아니라 **직접 그린 행·칩·탭**이다. 생김새로는 그게 눌리는
/// 물건인지 알 수 없어서, 커서가 유일한 "여기 누를 수 있다"는 신호가 된다. 없으면 사용자는 눌러보고 나서야 안다.
///
/// **push/pop이 아니라 set을 쓴다.** push/pop은 hover 종료 이벤트를 한 번이라도 놓치면(메뉴 창이
/// 위에 뜨거나, 뷰가 hover 중에 사라지면 실제로 놓친다) 커서 스택이 어긋난 채 영영 남는다 —
/// 손가락 커서가 창 전체에 들러붙는다. `set`은 스택을 안 쌓으므로 그 사고가 구조적으로 불가능하다.
/// 대신 벗어날 때 화살표로 되돌려야 하고, 그마저 놓치면 다음 hover가 바로잡는다(자기 치유).
extension View {
    /// 누를 수 있는 것 — 손가락.
    func clickCursor() -> some View { cursor(.pointingHand) }

    /// 커서를 지정한 모양으로 바꾼다(hover 동안).
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}
