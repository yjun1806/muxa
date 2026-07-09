import AppKit

/// 분할 사이 구분선. 드래그하면 인접 두 자식의 크기 가중치를 이동시킨다.
///
/// 드래그는 modal event loop로 처리한다 — 리사이즈 도중 WorkspaceView가 relayout하며
/// 이 뷰를 교체해도 루프가 마우스 이벤트를 독점하므로 드래그가 끊기지 않는다.
final class DividerView: NSView {
    private let dir: Dir
    private let onResize: (CGFloat) -> Void

    init(divider: Divider, onResize: @escaping (CGFloat) -> Void) {
        self.dir = divider.dir
        self.onResize = onResize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
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
            onResize(cur - last)
            last = cur
        }
    }
}
