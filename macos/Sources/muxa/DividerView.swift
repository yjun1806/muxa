import AppKit

/// 분할 사이 드래그 리사이즈 구분선. 드래그하면 인접 두 자식의 크기 가중치를 이동시킨다.
///
/// 뷰는 relayout 사이에 재사용된다(key로 매칭) — 매 레이아웃마다 재생성하면 레이아웃 도중
/// 서브뷰 추가/제거가 다시 레이아웃을 트리거해 무한 루프(창 크래시)가 된다.
/// 그래서 현재 divider 스냅샷을 프로퍼티로 갱신하고, 리사이즈 시 그 값을 콜백에 넘긴다.
///
/// 드래그는 modal event loop로 처리한다 — 리사이즈 도중 WorkspaceView가 relayout해도
/// 루프가 마우스 이벤트를 독점하므로 드래그가 끊기지 않는다.
final class DividerView: NSView {
    private let dir: Dir
    var divider: SplitDivider
    private let onResize: (SplitDivider, CGFloat) -> Void

    init(divider: SplitDivider, onResize: @escaping (SplitDivider, CGFloat) -> Void) {
        self.dir = divider.dir
        self.divider = divider
        self.onResize = onResize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: dir == .row ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, let superview else { return }
        func pointer(_ e: NSEvent) -> CGFloat {
            let p = superview.convert(e.locationInWindow, from: nil)
            return dir == .row ? p.x : p.y
        }
        var last = pointer(event)
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let cur = pointer(e)
            onResize(divider, cur - last)
            last = cur
        }
    }
}
