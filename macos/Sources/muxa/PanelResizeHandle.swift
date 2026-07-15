import AppKit
import SwiftUI

/// 우측 도구 패널(익스플로러·Git)을 좌측 경계 드래그로 리사이즈하는 controlled 래퍼.
/// 패널 콘텐츠의 좌측 경계 위에 넓은(11px) AppKit 히트영역을 얹는다.
///
/// 부드러움의 핵심: 드래그 중엔 로컬 `@State(liveWidth)`로만 폭을 갱신한다 — AppState 같은
/// 전역 관측 상태를 매 프레임 건드리면 상위(workspaceColumn)의 무거운 하위 트리(터미널·패널)가
/// 통째로 재평가돼 버벅인다. 손을 뗀 순간에만 `onCommit`으로 상위에 한 번 커밋(영속 저장)한다.
///
/// 핸들은 콘텐츠 **위 overlay**로 얹어 경계에 걸치게 둔다 — 콘텐츠(오른쪽)에도, 왼쪽 이웃
/// 패널에도 덮이지 않아 11px 전체가 늘 최상단에서 잡힌다. 탐색기·Git이 함께 떠도 그 사이
/// 경계가 정상 동작한다. 드래그는 SwiftUI 제스처가 아니라 AppKit 핸들이 처리한다 — 창이
/// `isMovableByWindowBackground`라 제스처가 새면 창이 통째로 이동하기 때문.
///
/// controlled: 커밋된 폭(`width`)은 상위(AppState)가 소유하고, 변경은 `onCommit(newWidth)`로 위임한다.
struct ResizablePanel<Content: View>: View {
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let onCommit: (_ newWidth: CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    /// 히트영역 폭(px). 시각적 구분선(1px)은 이 폭의 정중앙에 그린다.
    private static var hitWidth: CGFloat { 11 }

    /// 드래그 중 실시간 폭(비영속). nil이면 드래그 중이 아니고 상위의 `width`를 그대로 쓴다.
    @State private var liveWidth: CGFloat?
    /// 드래그 시작 시점의 폭 — 이동량은 시작점 기준 누적이라 기준값을 고정해야 한다.
    @State private var startWidth: CGFloat = 0

    /// 지금 그릴 폭 — 드래그 중이면 liveWidth, 아니면 상위가 커밋한 width.
    private var effectiveWidth: CGFloat { liveWidth ?? width }

    var body: some View {
        // 경계선(1px)은 레이아웃에 고정 — 픽셀 정렬돼 한 줄만 깔끔하게 그려진다.
        HStack(spacing: 0) {
            Rectangle().fill(Color.pBorder).frame(width: 1)
            // 왼쪽 정렬 + 클립 — 폭을 콘텐츠 최소너비보다 좁히면 기본 가운데 정렬이 왼쪽으로도 넘쳐
            // 경계선·핸들을 덮어 기준점이 어긋난다. 왼쪽에 붙여 오른쪽으로만 잘리게 한다.
            content()
                .frame(width: effectiveWidth, alignment: .leading)
                .clipped()
        }
        // 경계선에서 오른쪽(자기 패널 안쪽)으로만 뻗는 투명 히트/커서 오버레이(콘텐츠 위, 시각적 선 없음).
        // 좌우로 걸치면 왼쪽 이웃 패널의 리스트뷰(NSScrollView)에 커서 트래킹을 뺏긴다 — 이웃과
        // 겹치지 않게 안쪽으로만 두면 커서가 경계선에서 정확히 바뀐다. leading 정렬 → x=0(경계)부터 시작.
        .overlay(alignment: .leading) {
            handle
        }
    }

    /// 투명한 11px 히트영역. AppKit 핸들이 드래그·커서를 담당한다.
    /// 패널이 오른쪽에 있어 왼쪽으로 끌면 넓어진다(delta = -dx).
    private var handle: some View {
        PanelResizeDivider(
            onBegan: { startWidth = width },
            onChanged: { dx in liveWidth = clamp(startWidth - dx) },
            onEnded: { dx in
                let final = clamp(startWidth - dx)
                liveWidth = nil
                onCommit(final)
            }
        )
        .frame(width: Self.hitWidth)
    }

    private func clamp(_ w: CGFloat) -> CGFloat {
        min(max(w, range.lowerBound), range.upperBound)
    }
}

/// 왼쪽 칼럼을 **우측 경계** 드래그로 리사이즈하는 controlled 래퍼 — `ResizablePanel`의 좌우 대칭.
/// 서비스 도크의 [좌: 목록 | 우: 터미널] 분할에 쓴다. 왼쪽에 있어 오른쪽으로 끌면 넓어진다(delta = +dx).
struct ResizableLeftColumn<Content: View>: View {
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let onCommit: (_ newWidth: CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    private static var hitWidth: CGFloat { 11 }
    @State private var liveWidth: CGFloat?
    @State private var startWidth: CGFloat = 0
    private var effectiveWidth: CGFloat { liveWidth ?? width }

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(width: effectiveWidth, alignment: .leading)
                .clipped()
            Rectangle().fill(Color.pBorder).frame(width: 1)
        }
        // 핸들은 우측 경계에 얹는다(콘텐츠 안쪽으로만 뻗어 오른쪽 터미널의 트래킹을 뺏지 않는다).
        .overlay(alignment: .trailing) { handle }
    }

    private var handle: some View {
        PanelResizeDivider(
            onBegan: { startWidth = width },
            onChanged: { dx in liveWidth = clamp(startWidth + dx) },
            onEnded: { dx in
                let final = clamp(startWidth + dx)
                liveWidth = nil
                onCommit(final)
            }
        )
        .frame(width: Self.hitWidth)
    }

    private func clamp(_ w: CGFloat) -> CGFloat {
        min(max(w, range.lowerBound), range.upperBound)
    }
}

/// 좌우 리사이즈 드래그를 확실히 잡는 AppKit 핸들. 창 이동(isMovableByWindowBackground)을
/// 막고(`mouseDownCanMoveWindow=false`) 마우스 트래킹으로 시작점 대비 x 이동량(dx)을 콜백한다.
private struct PanelResizeDivider: NSViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (_ dx: CGFloat) -> Void
    let onEnded: (_ dx: CGFloat) -> Void

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let v = ResizeHandleNSView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: ResizeHandleNSView, context: Context) {
        apply(to: v)
    }

    private func apply(to v: ResizeHandleNSView) {
        v.onBegan = onBegan
        v.onChanged = onChanged
        v.onEnded = onEnded
    }
}

final class ResizeHandleNSView: NSView {
    var onBegan: (() -> Void)?
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    /// 드래그 시작 x(창 좌표). 창 좌표계는 오른쪽으로 x가 증가한다.
    private var startX: CGFloat = 0
    private var tracking: NSTrackingArea?

    /// 이 뷰 위에서 시작한 마우스다운은 창을 움직이지 않는다 — 리사이즈만.
    override var mouseDownCanMoveWindow: Bool { false }

    /// 좌우 리사이즈 커서 — SwiftUI 호스팅에선 resetCursorRects가 불안정해 트래킹 영역으로 건다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(t)
        tracking = t
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        startX = event.locationInWindow.x
        onBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set() // 드래그 중 커서 유지
        onChanged?(event.locationInWindow.x - startX)
    }

    override func mouseUp(with event: NSEvent) {
        onEnded?(event.locationInWindow.x - startX)
    }
}
