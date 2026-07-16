import XCTest
@testable import muxa

/// 칸 상태 표시 설정 — 로드/클램프/영속. 뷰 없이 못 박는다(순수 로직).
final class PaneIndicatorSettingsTests: XCTestCase {

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.paneindicator.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.paneindicator.\(name)")
        return d
    }

    func testDefaultsAreBackwardCompatible() {
        let s = PaneIndicatorSettings(defaults: suite())
        XCTAssertEqual(s.form, .ring)          // 기존 룩(전체 링) 유지
        XCTAssertEqual(s.thickness, 2)
        XCTAssertEqual(s.bracketInset, 7)
        XCTAssertFalse(s.clearOnFocus)         // 기본 = 포커스해도 유지
    }

    func testOutOfRangeStoredValuesClampOnLoad() {
        let d = suite()
        d.set(999, forKey: "muxa.paneindicator.thickness")
        d.set(-5, forKey: "muxa.paneindicator.bracketInset")
        let s = PaneIndicatorSettings(defaults: d)
        XCTAssertEqual(s.thickness, PaneIndicatorSettings.thicknessRange.upperBound)
        XCTAssertEqual(s.bracketInset, PaneIndicatorSettings.bracketInsetRange.lowerBound)
    }

    func testUnknownFormFallsBackToRing() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.paneindicator.form")
        XCTAssertEqual(PaneIndicatorSettings(defaults: d).form, .ring)
    }

    func testWritePersistsAndReloads() {
        let d = suite()
        let s = PaneIndicatorSettings(defaults: d)
        s.form = .bracket
        s.thickness = 4
        s.clearOnFocus = true
        let reloaded = PaneIndicatorSettings(defaults: d)
        XCTAssertEqual(reloaded.form, .bracket)
        XCTAssertEqual(reloaded.thickness, 4)
        XCTAssertTrue(reloaded.clearOnFocus)
    }

    func testEveryFormHasLabel() {
        for form in PaneIndicatorForm.allCases {
            XCTAssertFalse(form.label.isEmpty, "\(form.rawValue) 라벨 누락")
        }
    }
}
