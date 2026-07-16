import SwiftUI

/// 탭·활성 탭 스타일의 사용자 설정 — 종합 설정 패널에서 바꾸고 UserDefaults에 즉시 영속한다.
///
/// 값은 순수하다(치수·enum). 이 값을 Bonsplit `Appearance`로 옮기는 일은 `BonsplitChrome.applyTabStyle`이,
/// 열린 칸에 라이브로 미는 일은 `AppState.reapplyTabAppearance`가 맡는다(경계 분리).
@Observable
final class TabStyleSettings {
    @MainActor static let shared = TabStyleSettings()

    /// 활성 탭이 "이게 선택됐다"를 말하는 방식 — 아티팩트 견본 7종과 짝.
    enum ActiveStyle: String, CaseIterable, Identifiable {
        case card       // 면(콘텐츠색) + 하단 선 — 현재 기본
        case underline  // 가장자리 밑줄
        case topRule    // 상단 선
        case insetBar   // 인셋 accent bar(둥근 밑줄)
        case pill       // 떠 있는 캡슐
        case block      // 꽉 찬 각진 면
        case minimal    // 굵기·틴트만

        var id: String { rawValue }

        var label: String {
            switch self {
            case .card: return "카드"
            case .underline: return "밑줄"
            case .topRule: return "상단선"
            case .insetBar: return "인셋바"
            case .pill: return "pill"
            case .block: return "블록"
            case .minimal: return "미니멀"
            }
        }
    }

    var activeStyle: ActiveStyle { didSet { defaults.set(activeStyle.rawValue, forKey: Self.key("activeStyle")) } }
    /// 탭 좌우 패딩(2~12).
    var horizontalPadding: Double { didSet { defaults.set(horizontalPadding, forKey: Self.key("hPadding")) } }
    /// 활성 면(카드·pill)의 모서리 반경(0~14). 밑줄/블록엔 영향 없음.
    var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: Self.key("cornerRadius")) } }
    /// 지시선 두께(0~4). 면 계열(pill·블록·미니멀)엔 영향 없음.
    var indicatorThickness: Double { didSet { defaults.set(indicatorThickness, forKey: Self.key("indicatorThickness")) } }

    /// 슬라이더 범위(뷰와 클램프가 한 출처를 쓰게).
    static let paddingRange: ClosedRange<Double> = 2...12
    static let radiusRange: ClosedRange<Double> = 0...14
    static let thicknessRange: ClosedRange<Double> = 0...4

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 기본값 = 현재 muxa 룩(카드 + 패딩 4 + 반경 10 + 지시선 2).
        activeStyle = defaults.string(forKey: Self.key("activeStyle")).flatMap(ActiveStyle.init(rawValue:)) ?? .card
        horizontalPadding = Self.stored(defaults, "hPadding", default: 4, in: Self.paddingRange)
        cornerRadius = Self.stored(defaults, "cornerRadius", default: 10, in: Self.radiusRange)
        indicatorThickness = Self.stored(defaults, "indicatorThickness", default: 2, in: Self.thicknessRange)
    }

    private static func stored(_ d: UserDefaults, _ name: String, default def: Double, in range: ClosedRange<Double>) -> Double {
        guard d.object(forKey: key(name)) != nil else { return def }
        return min(max(d.double(forKey: key(name)), range.lowerBound), range.upperBound)
    }

    private static func key(_ name: String) -> String { "muxa.tabstyle.\(name)" }
}

/// 한 스타일이 만들어내는 Bonsplit knob 묶음 — 순수 값. `BonsplitChrome.applyTabStyle`이 소비한다.
struct TabStyleKnobs {
    var tabCornerRadius: CGFloat = 0
    var tabTopInset: CGFloat = 0
    var indicatorAtBottom: Bool = true
    var activeIndicatorHeight: CGFloat = 0
    var inactiveIndicatorHeight: CGFloat = 0
    var indicatorInset: CGFloat = 0
    var indicatorCornerRadius: CGFloat = 0
    var fillCornerRadius: CGFloat?
    var fillVInset: CGFloat = 0
    var fillHInset: CGFloat = 0
    /// 활성 탭 면을 콘텐츠색(bg)으로 채울지 — false면 탭바 색(면이 안 보임, 선·굵기만 신호).
    var filled: Bool = false
    var bold: Bool = true
}

extension TabStyleSettings {
    /// 스타일 + 사용자 슬라이더(반경·두께) → knob 묶음. 스타일별 고정 상수(카드의 topInset 등)는 여기 산다.
    static func knobs(for style: ActiveStyle, radius: CGFloat, thickness: CGFloat) -> TabStyleKnobs {
        switch style {
        case .card:
            return TabStyleKnobs(tabCornerRadius: radius, tabTopInset: 3, indicatorAtBottom: true,
                                 activeIndicatorHeight: thickness, inactiveIndicatorHeight: max(0, thickness - 1),
                                 filled: true)
        case .underline:
            return TabStyleKnobs(indicatorAtBottom: true, activeIndicatorHeight: thickness,
                                 inactiveIndicatorHeight: max(0, thickness - 1), filled: false)
        case .topRule:
            return TabStyleKnobs(indicatorAtBottom: false, activeIndicatorHeight: thickness,
                                 inactiveIndicatorHeight: max(0, thickness - 1), filled: false)
        case .insetBar:
            let h = max(thickness, 3)
            return TabStyleKnobs(indicatorAtBottom: true, activeIndicatorHeight: h, inactiveIndicatorHeight: h,
                                 indicatorInset: 10, indicatorCornerRadius: h / 2, filled: false)
        case .pill:
            return TabStyleKnobs(activeIndicatorHeight: 0, inactiveIndicatorHeight: 0,
                                 fillCornerRadius: min(max(radius, 4), 9), fillVInset: 4, fillHInset: 3, filled: true)
        case .block:
            return TabStyleKnobs(activeIndicatorHeight: 0, inactiveIndicatorHeight: 0, filled: true)
        case .minimal:
            return TabStyleKnobs(activeIndicatorHeight: 0, inactiveIndicatorHeight: 0, filled: false)
        }
    }
}
