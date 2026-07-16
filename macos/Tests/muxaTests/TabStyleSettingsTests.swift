import XCTest
@testable import muxa

/// 탭 스타일 설정 — 순수 로직(스타일→knob 매핑)과 로드/클램프. 뷰 없이 못 박는다.
final class TabStyleSettingsTests: XCTestCase {

    // MARK: - knobs 매핑 불변식

    private func knobs(_ style: TabStyleSettings.ActiveStyle,
                       radius: CGFloat = 10, thickness: CGFloat = 2) -> TabStyleKnobs {
        TabStyleSettings.knobs(for: style, radius: radius, thickness: thickness)
    }

    func testCardIsFilledCardWithBottomRule() {
        let k = knobs(.card, radius: 8, thickness: 2)
        XCTAssertTrue(k.filled)                       // 면(콘텐츠색)으로 채운다
        XCTAssertEqual(k.tabCornerRadius, 8)          // 반경 슬라이더가 카드 모서리로
        XCTAssertEqual(k.tabTopInset, 3)
        XCTAssertTrue(k.indicatorAtBottom)
        XCTAssertEqual(k.activeIndicatorHeight, 2)    // 두께 슬라이더가 지시선으로
        XCTAssertNil(k.fillCornerRadius)              // pill 아님
    }

    func testUnderlineHasNoFillBottomRule() {
        let k = knobs(.underline, thickness: 2)
        XCTAssertFalse(k.filled)                      // 면 없음
        XCTAssertTrue(k.indicatorAtBottom)
        XCTAssertEqual(k.activeIndicatorHeight, 2)
        XCTAssertEqual(k.tabCornerRadius, 0)
        XCTAssertNil(k.fillCornerRadius)
    }

    func testTopRuleDrawsAtTop() {
        XCTAssertFalse(knobs(.topRule).indicatorAtBottom)
        XCTAssertFalse(knobs(.topRule).filled)
    }

    func testInsetBarIsInsetAndRounded() {
        let k = knobs(.insetBar, thickness: 2)
        let h = max(CGFloat(2), 3)                    // 최소 3
        XCTAssertEqual(k.indicatorInset, 10)          // 좌우로 물린다
        XCTAssertEqual(k.activeIndicatorHeight, h)
        XCTAssertEqual(k.indicatorCornerRadius, h / 2) // 끝이 둥글다
        XCTAssertFalse(k.filled)
    }

    func testPillIsFloatingCapsuleNoIndicator() {
        let k = knobs(.pill, radius: 7)
        XCTAssertNotNil(k.fillCornerRadius)           // 네 모서리 둥근 면
        XCTAssertTrue(k.filled)
        XCTAssertEqual(k.activeIndicatorHeight, 0)    // 지시선 없음
        XCTAssertGreaterThan(k.fillVInset, 0)         // 위아래로 떠 있어야 캡슐로 읽힌다
    }

    func testPillFillRadiusClampedTo4Through9() {
        XCTAssertEqual(knobs(.pill, radius: 0).fillCornerRadius, 4)   // 하한
        XCTAssertEqual(knobs(.pill, radius: 100).fillCornerRadius, 9) // 상한
        XCTAssertEqual(knobs(.pill, radius: 6).fillCornerRadius, 6)
    }

    func testBlockIsSquareFilledNoLine() {
        let k = knobs(.block)
        XCTAssertTrue(k.filled)
        XCTAssertEqual(k.activeIndicatorHeight, 0)
        XCTAssertNil(k.fillCornerRadius)
    }

    func testMinimalHasOnlyWeightSignal() {
        let k = knobs(.minimal)
        XCTAssertFalse(k.filled)                      // 면 없음
        XCTAssertEqual(k.activeIndicatorHeight, 0)    // 선 없음
        XCTAssertNil(k.fillCornerRadius)
        XCTAssertTrue(k.bold)                         // 굵기만이 유일한 신호
    }

    func testEveryStyleMapsWithoutTrap() {
        // 모든 스타일이 유효한 knob을 낸다(누락 case 방지) — inactive ≤ active 두께.
        for style in TabStyleSettings.ActiveStyle.allCases {
            let k = knobs(style, thickness: 1)
            XCTAssertLessThanOrEqual(k.inactiveIndicatorHeight, max(k.activeIndicatorHeight, 3))
        }
    }

    // MARK: - 로드 / 클램프 / 영속

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.tabstyle.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.tabstyle.\(name)")
        return d
    }

    func testDefaultsMatchCurrentLook() {
        let s = TabStyleSettings(defaults: suite())
        XCTAssertEqual(s.activeStyle, .card)
        XCTAssertEqual(s.horizontalPadding, 4)
        XCTAssertEqual(s.cornerRadius, 10)
        XCTAssertEqual(s.indicatorThickness, 2)
    }

    func testOutOfRangeStoredValuesClampOnLoad() {
        let d = suite()
        d.set(999, forKey: "muxa.tabstyle.hPadding")
        d.set(-5, forKey: "muxa.tabstyle.cornerRadius")
        let s = TabStyleSettings(defaults: d)
        XCTAssertEqual(s.horizontalPadding, TabStyleSettings.paddingRange.upperBound)
        XCTAssertEqual(s.cornerRadius, TabStyleSettings.radiusRange.lowerBound)
    }

    func testUnknownStyleFallsBackToCard() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.tabstyle.activeStyle")
        XCTAssertEqual(TabStyleSettings(defaults: d).activeStyle, .card)
    }

    func testWritePersistsAndReloads() {
        let d = suite()
        let s = TabStyleSettings(defaults: d)
        s.activeStyle = .pill
        s.horizontalPadding = 8
        // 새 인스턴스가 같은 저장소에서 읽으면 값이 살아 있다.
        let reloaded = TabStyleSettings(defaults: d)
        XCTAssertEqual(reloaded.activeStyle, .pill)
        XCTAssertEqual(reloaded.horizontalPadding, 8)
    }
}
