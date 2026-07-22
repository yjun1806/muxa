import SwiftUI

/// 줄바꿈 배치 — 가로로 채우다 폭을 넘으면 다음 줄로 내린다(HTML inline-wrap처럼).
/// 사이드바 뷰어 칩처럼 **개수를 알 수 없는 작은 조각들**을 좁은 폭에 흘려 담을 때 쓴다.
///
/// 순수 기하다 — 상태·부작용이 없다. 간격 두 축(칩 사이 가로 / 줄 사이 세로)만 받고,
/// 줄 나누는 판정(`rows`)은 부분뷰의 고유 크기만 보는 순수 함수다. 왼쪽 정렬, 각 줄 세로 중앙.
struct FlowLayout: Layout {
    /// 칩 사이 가로 간격.
    var spacing: CGFloat = Space.xs
    /// 줄 사이 세로 간격.
    var lineSpacing: CGFloat = Space.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: 순수 판정 — 부분뷰를 줄 단위로 가른다(고유 크기만 본다).

    private struct Row { var indices: [Int]; var width: CGFloat; var height: CGFloat }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: [], width: 0, height: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // 첫 칸은 폭 넘어도 그 줄에 둔다 — 안 그러면 빈 줄만 쌓이고 무한 루프처럼 보인다.
            let advance = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && advance > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = advance
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
