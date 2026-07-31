import Foundation
import Testing
@testable import muxa

/// 탭 스타일 설정 — 순수 로직(스타일→knob 매핑)과 로드/클램프. 뷰 없이 못 박는다.
struct TabStyleSettingsTests {

    // MARK: - knobs 매핑 불변식

    private func knobs(_ style: TabStyleSettings.ActiveStyle,
                       radius: CGFloat = 10, thickness: CGFloat = 2) -> TabStyleKnobs {
        TabStyleSettings.knobs(for: style, radius: radius, thickness: thickness)
    }

    @Test func testCardIsFilledCardWithBottomRule() {
        let k = knobs(.card, radius: 8, thickness: 2)
        #expect(k.filled)                       // 면(콘텐츠색)으로 채운다
        #expect(k.tabCornerRadius == 8)          // 반경 슬라이더가 카드 모서리로
        #expect(k.tabTopInset == 3)
        #expect(k.indicatorAtBottom)
        #expect(k.activeIndicatorHeight == 2)    // 두께 슬라이더가 지시선으로
        #expect(k.fillCornerRadius == nil)              // pill 아님
    }

    @Test func testUnderlineHasNoFillBottomRule() {
        let k = knobs(.underline, thickness: 2)
        #expect(!(k.filled))                      // 면 없음
        #expect(k.indicatorAtBottom)
        #expect(k.activeIndicatorHeight == 2)
        #expect(k.tabCornerRadius == 0)
        #expect(k.fillCornerRadius == nil)
    }

    @Test func testTopRuleDrawsAtTop() {
        #expect(!(knobs(.topRule).indicatorAtBottom))
        #expect(!(knobs(.topRule).filled))
    }

    @Test func testInsetBarIsInsetAndRounded() {
        let k = knobs(.insetBar, thickness: 2)
        let h = max(CGFloat(2), 3)                    // 최소 3
        #expect(k.indicatorInset == 10)          // 좌우로 물린다
        #expect(k.activeIndicatorHeight == h)
        #expect(k.indicatorCornerRadius == h / 2) // 끝이 둥글다
        #expect(!(k.filled))
    }

    @Test func testPillIsFloatingCapsuleNoIndicator() {
        let k = knobs(.pill, radius: 7)
        #expect(k.fillCornerRadius != nil)           // 네 모서리 둥근 면
        #expect(k.filled)
        #expect(k.activeIndicatorHeight == 0)    // 지시선 없음
        #expect(k.fillVInset > 0)         // 위아래로 떠 있어야 캡슐로 읽힌다
    }

    @Test func testPillFillRadiusClampedTo4Through9() {
        #expect(knobs(.pill, radius: 0).fillCornerRadius == 4)   // 하한
        #expect(knobs(.pill, radius: 100).fillCornerRadius == 9) // 상한
        #expect(knobs(.pill, radius: 6).fillCornerRadius == 6)
    }

    @Test func testBlockIsSquareFilledNoLine() {
        let k = knobs(.block)
        #expect(k.filled)
        #expect(k.activeIndicatorHeight == 0)
        #expect(k.fillCornerRadius == nil)
    }

    @Test func testMinimalHasOnlyWeightSignal() {
        let k = knobs(.minimal)
        #expect(!(k.filled))                      // 면 없음
        #expect(k.activeIndicatorHeight == 0)    // 선 없음
        #expect(k.fillCornerRadius == nil)
        #expect(k.bold)                         // 굵기만이 유일한 신호
    }

    @Test func testEveryStyleMapsWithoutTrap() {
        // 모든 스타일이 유효한 knob을 낸다(누락 case 방지) — inactive ≤ active 두께.
        for style in TabStyleSettings.ActiveStyle.allCases {
            let k = knobs(style, thickness: 1)
            #expect(k.inactiveIndicatorHeight <= max(k.activeIndicatorHeight, 3))
        }
    }

    // MARK: - 로드 / 클램프 / 영속

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.tabstyle.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.tabstyle.\(name)")
        return d
    }

    @Test func testDefaultsMatchCurrentLook() {
        let s = TabStyleSettings(defaults: suite())
        #expect(s.activeStyle == .card)
        #expect(s.horizontalPadding == 4)
        #expect(s.cornerRadius == 10)
        #expect(s.indicatorThickness == 2)
    }

    @Test func testOutOfRangeStoredValuesClampOnLoad() {
        let d = suite()
        d.set(999, forKey: "muxa.tabstyle.hPadding")
        d.set(-5, forKey: "muxa.tabstyle.cornerRadius")
        let s = TabStyleSettings(defaults: d)
        #expect(s.horizontalPadding == TabStyleSettings.paddingRange.upperBound)
        #expect(s.cornerRadius == TabStyleSettings.radiusRange.lowerBound)
    }

    @Test func testUnknownStyleFallsBackToCard() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.tabstyle.activeStyle")
        #expect(TabStyleSettings(defaults: d).activeStyle == .card)
    }

    @Test func testWritePersistsAndReloads() {
        let d = suite()
        let s = TabStyleSettings(defaults: d)
        s.activeStyle = .pill
        s.horizontalPadding = 8
        // 새 인스턴스가 같은 저장소에서 읽으면 값이 살아 있다.
        let reloaded = TabStyleSettings(defaults: d)
        #expect(reloaded.activeStyle == .pill)
        #expect(reloaded.horizontalPadding == 8)
    }
}
