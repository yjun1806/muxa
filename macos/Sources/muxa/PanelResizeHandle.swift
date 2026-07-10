import AppKit
import SwiftUI

/// 우측 도구 패널(익스플로러·Git)의 좌측 경계 리사이즈 핸들.
/// 1px 구분선 위에 넓은(9px) 히트영역을 얹어 드래그로 폭을 조절한다. 패널이 오른쪽에 있어
/// 왼쪽으로 끌면 넓어진다(delta = -translation.width). 폭 상태는 상위(AppState)가 소유·영속한다.
///
/// controlled: 현재 폭(`width`)을 받아 그리고, 변경은 `onResize(newWidth, committed)`로 위임한다.
/// committed=false는 드래그 중(비영속 갱신), true는 손을 뗀 순간(영속 저장) — 매 프레임 디스크 쓰기를 피한다.
struct PanelResizeHandle: View {
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let onResize: (_ newWidth: CGFloat, _ committed: Bool) -> Void

    /// 드래그 시작 시점의 폭 — DragGesture.translation은 시작점 기준 누적이라 기준값을 고정해야 한다.
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.pBorder)
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        // 좌우 리사이즈 커서 — 히트영역에 들어오면 표시, 나가면 되돌린다.
                        if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                onResize(clamp(base - value.translation.width), false)
                            }
                            .onEnded { value in
                                let base = startWidth ?? width
                                onResize(clamp(base - value.translation.width), true)
                                startWidth = nil
                            }
                    )
            }
    }

    private func clamp(_ w: CGFloat) -> CGFloat {
        min(max(w, range.lowerBound), range.upperBound)
    }
}
