import SwiftUI

/// 개수 배지 — 이름 옆 캡슐 숫자(워크스페이스=프로젝트 수 · 프로젝트=열린 탭 수).
/// 접혀 있어도 "안에 몇 개"가 보인다(orca SectionMetricsBadge). 의미 라벨은 호출부가
/// `.accessibilityLabel`로 붙인다 — 무엇의 개수인지는 자리가 안다.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.muxaMono(.micro))
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.tight)
            .background(Capsule().fill(Color.pBtnHover))
            .overlay(Capsule().stroke(Color.pBorder, lineWidth: RowHeight.hairline))
    }
}
