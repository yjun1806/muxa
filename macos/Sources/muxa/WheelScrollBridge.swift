import AppKit

/// 휠 마우스로 **가로 전용 스크롤 영역**(탭바·서브탭 바)을 스크롤하게 해주는 경계 타입.
///
/// AppKit은 가로 전용 NSScrollView에 세로 휠 델타를 자동으로 넘기지 않는다(⇧+휠만 가로로 간다).
/// 트랙패드는 델타에 가로 성분이 실려 있어 원래 잘 되지만, 휠 마우스는 그렇지 않아 탭바가 "스크롤이
/// 막힌 것처럼" 보인다. 그래서 세로 휠을 그 스크롤뷰의 가로 이동으로 옮겨준다.
///
/// **가로로만 스크롤되는 뷰에만 적용한다** — 세로 스크롤이 정상인 곳(익스플로러·Git 패널·뷰어)은
/// 손대지 않는다. 그 판정을 이벤트마다 다시 하므로 오작동해도 그 이벤트 하나에 그친다.
@MainActor
enum WheelScrollBridge {
    /// 로컬 scrollWheel 모니터를 설치한다. 반환값(모니터 토큰)은 앱 수명 동안 보관한다.
    static func install() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { redirect(event) ? nil : event }
        }
    }

    /// 이 휠 이벤트를 가로 스크롤로 돌렸으면 true(= 이벤트 소비).
    private static func redirect(_ event: NSEvent) -> Bool {
        // 이미 가로 성분이 있으면(트랙패드·⇧+휠) AppKit이 알아서 처리한다.
        guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else { return false }
        guard let window = event.window,
              let hit = window.contentView?.hitTest(event.locationInWindow),
              let scrollView = horizontalOnlyScrollView(from: hit) else { return false }

        let clip = scrollView.contentView
        let content = scrollView.documentView?.frame.width ?? 0
        let maxX = max(0, content - clip.bounds.width)
        // 휠 한 칸(line)은 픽셀 델타가 아니라 "줄 수"라 그대로 쓰면 너무 느리다 — 줄 높이만큼 곱한다.
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * lineHeight
        let x = min(max(clip.bounds.origin.x - step, 0), maxX)
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// 휠 한 칸이 옮길 거리(pt) — macOS 기본 줄 스크롤 감각에 맞춘 값.
    private static let lineHeight: CGFloat = 16

    /// 히트한 뷰에서 위로 올라가며 "가로로만 스크롤되는" NSScrollView를 찾는다.
    /// 세로로도 스크롤되는 뷰(파일 트리·목록)를 만나면 즉시 포기한다 — 그건 휠의 원래 주인이다.
    private static func horizontalOnlyScrollView(from view: NSView) -> NSScrollView? {
        var node: NSView? = view
        while let current = node {
            if let scrollView = current as? NSScrollView {
                let clip = scrollView.contentView.bounds.size
                let content = scrollView.documentView?.frame.size ?? .zero
                let scrollsVertically = content.height > clip.height + 1
                let scrollsHorizontally = content.width > clip.width + 1
                return (scrollsHorizontally && !scrollsVertically) ? scrollView : nil
            }
            node = current.superview
        }
        return nil
    }
}
