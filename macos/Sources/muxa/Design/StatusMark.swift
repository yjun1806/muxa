import SwiftUI

/// 상태 톤을 색·글리프·**모션**으로 그리는 마크 — `StatusStyle`(색·글리프 SSOT) 위에 표현만 얹는다.
///
/// - 작업중(active) = 회전 스피너(인디고) — "지금 돌고 있다"를 모양·움직임으로.
/// - 대기(attention) = 글리프 펄스(로즈) — "나를 기다린다".
/// - 완료·실패·실행전 = 정적 글리프. 유휴(quiet) = 빈 슬롯(폭만 유지).
///
/// 시간구동(TimelineView·symbolEffect)이라 리스트 행 재활용에도 애니메이션이 끊기거나 남지 않는다.
/// reduce-motion이면 스피너는 멈춘 아크, 펄스는 정적 글리프로 떨어진다(움직임 없이 의미는 유지).
struct StatusMark: View {
    let tone: StatusTone
    var size: CGFloat = IconSize.statusGlyph

    var body: some View {
        switch tone {
        case .quiet:
            Color.clear.frame(width: size, height: size)
        case .active:
            SpinnerArc(color: StatusStyle.color(tone), lineWidth: max(size * 0.16, 1.5))
                .frame(width: size, height: size)
        case .attention:
            glyph.symbolEffect(.pulse, options: .repeating)
        default:
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: StatusStyle.glyph(tone))
            .font(.muxa(.micro, weight: .semibold))
            .foregroundStyle(StatusStyle.color(tone))
            .frame(width: size, height: size)
    }
}

/// 시간구동 스피너 아크 — 원의 70%만 그려 회전시킨다. `repeatForever` 애니메이션과 달리
/// `TimelineView(.animation)`이라 행 재활용에도 안전하고 남은 애니메이션이 없다.
struct SpinnerArc: View {
    let color: Color
    var lineWidth: CGFloat = 2
    /// 한 바퀴에 걸리는 시간(초).
    var period: Double = 1.1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            arc(angle: -90)
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: period) / period) * 360
                arc(angle: angle)
            }
        }
    }

    private func arc(angle: Double) -> some View {
        Circle().trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .padding(lineWidth / 2)
    }
}
