import AppKit
import SwiftUI

/// 커스텀 컨텍스트 메뉴를 띄우는 경계 타입 — 떠 있는 판 하나(`FloatingPanelHost`)를 재사용해 열고 닫는다.
/// 창·이벤트·경계 클램프는 전부 호스트가 맡고, 여기는 "메뉴는 커서 자리에서 펼친다"만 정한다.
/// (푸터 팝오버는 같은 호스트를 `MuxaPopoverWindow`가 쓴다 — 둘이 한 세트로 보이는 이유.)
@MainActor
enum MuxaMenuWindow {
    private static let host = FloatingPanelHost()

    /// 스크린 좌표 지점에 메뉴를 띄운다. `onClose`는 닫힐 때 1회 호출(호출부의 열림 표시 해제용).
    static func show(_ items: [MuxaMenuItem], at point: NSPoint, onClose: (() -> Void)? = nil) {
        host.show(
            MuxaMenuView(items: items) { host.dismiss() }.floatingPanel(),
            at: .menu(point),
            onClose: onClose
        )
    }
}

// MARK: - 우클릭 캡처

extension View {
    /// 우클릭을 스크린 좌표로 받는다. 좌클릭은 그대로 아래 뷰(버튼)로 흘려보낸다.
    /// (⌃-클릭은 AppKit이 leftMouseDown으로 보내므로 여기 오지 않는다 — 크롬 UI에선 우클릭만 지원한다.)
    func onRightClick(perform action: @escaping (NSPoint) -> Void) -> some View {
        overlay(RightClickCatcher(onRightClick: action))
    }
}

/// 좌클릭은 투명하고 우클릭만 잡는 얇은 오버레이. 히트테스트를 현재 이벤트 종류로 갈라 이를 구현한다.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (NSPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? CatcherView)?.onRightClick = onRightClick
    }

    private final class CatcherView: NSView {
        var onRightClick: ((NSPoint) -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(NSEvent.mouseLocation)
        }

        /// 우클릭 이벤트일 때만 자신을 히트 대상으로 내민다 — 좌클릭은 아래 SwiftUI 버튼이 받는다.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}
