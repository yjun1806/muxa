import SwiftUI

/// 얇은 진행 막대 — 0~1 비율을 채움 폭으로 보여준다(사용량·진행률 공용).
///
/// 트랙은 같은 색의 옅은 틴트라 색 하나만 정하면 되고(`Pill`과 같은 규칙),
/// 값이 바뀌면 채움이 애니메이션으로 따라간다.
struct Meter: View {
    /// 0~1. 범위를 벗어나면 잘라낸다.
    let value: Double
    let color: Color
    var width: CGFloat = 30
    var height: CGFloat = 4

    private var ratio: Double { min(max(value, 0), 1) }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(color.opacity(0.18))
                .frame(width: width, height: height)
            if ratio > 0 {
                Capsule()
                    .fill(color)
                    // 아주 작은 값도 보이게 최소 폭을 높이만큼 준다(1%가 안 보이면 0%와 구분이 안 된다).
                    .frame(width: max(height, width * ratio), height: height)
            }
        }
        .frame(width: width, height: height)
        .animation(Motion.medium, value: ratio)
    }
}
