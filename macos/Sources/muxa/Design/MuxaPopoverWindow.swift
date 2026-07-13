import AppKit
import SwiftUI

/// 푸터 칩에서 여는 팝오버 — 커스텀 메뉴와 **같은 창·같은 표면**을 쓴다(`FloatingPanelHost` + `floatingPanel()`).
///
/// 시스템 `.popover`를 버린 이유: NSPopover는 화살표·배경 재질·모서리 반경·그림자를 앱이 정할 수 없다.
/// 같은 푸터에서 열리는 커스텀 메뉴가 바로 옆에 있는데 결이 다르면, 다듬어봐야 "다른 앱 두 개"로 보인다.
/// 화살표는 없앤다 — 어느 칩에서 나왔는지는 **칩이 열린 동안 눌린 채로 남는 것**(`FooterChip`)이 말해준다.
@MainActor
enum MuxaPopoverWindow {
    private static let host = FloatingPanelHost()

    /// 앵커(칩)의 스크린 사각형 위에 판을 띄운다.
    static func show(_ content: some View, above anchor: NSRect, onClose: @escaping () -> Void) {
        host.show(content.floatingPanel(), at: .above(anchor), onClose: onClose)
    }

    static func dismiss() { host.dismiss() }
}

extension View {
    /// 이 뷰(칩) 위에 커스텀 팝오버를 띄운다 — 시스템 `.popover`의 자리를 대신한다.
    func muxaPopover(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        modifier(MuxaPopoverModifier(isPresented: isPresented, popover: content))
    }
}

private struct MuxaPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let popover: () -> PopoverContent

    /// 앵커(칩)의 자리를 아는 유일한 통로. **좌표를 캐시하지 않고 열 때 읽는다** —
    /// 캐시하면 창이 움직이거나 푸터가 재배치될 때 낡은 자리에 팝오버가 뜬다.
    @State private var anchor = AnchorBox()

    func body(content: Content) -> some View {
        content
            .background(AnchorReader(box: anchor))
            .onChange(of: isPresented) { _, open in
                guard open else { return MuxaPopoverWindow.dismiss() }
                // 판이 닫히는 경로(바깥 클릭·Esc)는 여러 갈래다 — 전부 여기로 모아 바인딩을 되돌린다.
                MuxaPopoverWindow.show(popover(), above: anchor.screenRect) { isPresented = false }
            }
            .onDisappear { if isPresented { MuxaPopoverWindow.dismiss() } }
    }
}

/// 앵커 뷰의 스크린 사각형을 **필요할 때** 계산해 주는 상자.
@MainActor
private final class AnchorBox {
    weak var view: NSView?

    var screenRect: NSRect {
        guard let view, let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// 자기가 놓인 자리를 알려주는 투명 뷰 — SwiftUI 좌표계는 창 밖(스크린)을 모른다.
private struct AnchorReader: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }

    /// 자리만 차지하고 클릭은 아래(칩)로 흘려보낸다.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
