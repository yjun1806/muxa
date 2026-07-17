import XCTest
@testable import muxa

/// 사용량 표시 설정 — 로드/기본값/클램프와 위치 enum의 좌우·푸터 판정. 뷰 없이 못 박는다.
final class StatusBarSettingsTests: XCTestCase {

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.statusbar.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.statusbar.\(name)")
        return d
    }

    func testDefaultsPreserveExistingBehavior() {
        let s = StatusBarSettings(defaults: suite())
        XCTAssertTrue(s.showSessionReset)   // 세션 리셋만 표시(기존 동작)
        XCTAssertFalse(s.showWeeklyReset)
        XCTAssertFalse(s.showFable)
        XCTAssertEqual(s.position, .footerLeft)
        // 갱신 주기 설정은 없앴다 — 폴링 주기는 사용자가 아니라 엔드포인트 예산이 정하는 상수다(UsagePolicy).
    }

    func testUnknownPositionFallsBackToFooterLeft() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.statusbar.position")
        XCTAssertEqual(StatusBarSettings(defaults: d).position, .footerLeft)
    }

    func testTogglesPersistAndReload() {
        let d = suite()
        let s = StatusBarSettings(defaults: d)
        s.showWeeklyReset = true
        s.showFable = true
        s.position = .headerRight
        let reloaded = StatusBarSettings(defaults: d)
        XCTAssertTrue(reloaded.showWeeklyReset)
        XCTAssertTrue(reloaded.showFable)
        XCTAssertEqual(reloaded.position, .headerRight)
    }

    // MARK: - Position 판정

    func testPositionFooterVsHeader() {
        XCTAssertTrue(StatusBarSettings.Position.footerLeft.inFooter)
        XCTAssertTrue(StatusBarSettings.Position.footerRight.inFooter)
        XCTAssertFalse(StatusBarSettings.Position.headerLeft.inFooter)
        XCTAssertFalse(StatusBarSettings.Position.headerRight.inFooter)
    }

    func testPositionLeadingVsTrailing() {
        XCTAssertTrue(StatusBarSettings.Position.footerLeft.isLeading)
        XCTAssertTrue(StatusBarSettings.Position.headerLeft.isLeading)
        XCTAssertFalse(StatusBarSettings.Position.footerRight.isLeading)
        XCTAssertFalse(StatusBarSettings.Position.headerRight.isLeading)
    }

    func testAllPositionsHaveLabels() {
        for p in StatusBarSettings.Position.allCases {
            XCTAssertFalse(p.label.isEmpty)
        }
    }
}
