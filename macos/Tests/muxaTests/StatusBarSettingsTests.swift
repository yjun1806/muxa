import Foundation
import Testing
@testable import muxa

/// 사용량 표시 설정 — 로드/기본값/클램프와 위치 enum의 좌우·푸터 판정. 뷰 없이 못 박는다.
struct StatusBarSettingsTests {

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.statusbar.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.statusbar.\(name)")
        return d
    }

    @Test func defaultsPreserveExistingBehavior() {
        let s = StatusBarSettings(defaults: suite())
        #expect(s.showSessionReset)   // 세션 리셋만 표시(기존 동작)
        #expect(!s.showWeeklyReset)
        #expect(!s.showFable)
        #expect(s.position == .footerLeft)
        // 갱신 주기 설정은 없앴다 — 폴링 주기는 사용자가 아니라 엔드포인트 예산이 정하는 상수다(UsagePolicy).
    }

    @Test func unknownPositionFallsBackToFooterLeft() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.statusbar.position")
        #expect(StatusBarSettings(defaults: d).position == .footerLeft)
    }

    @Test func togglesPersistAndReload() {
        let d = suite()
        let s = StatusBarSettings(defaults: d)
        s.showWeeklyReset = true
        s.showFable = true
        s.position = .headerRight
        let reloaded = StatusBarSettings(defaults: d)
        #expect(reloaded.showWeeklyReset)
        #expect(reloaded.showFable)
        #expect(reloaded.position == .headerRight)
    }

    // MARK: - Position 판정

    @Test func positionFooterVsHeader() {
        #expect(StatusBarSettings.Position.footerLeft.inFooter)
        #expect(StatusBarSettings.Position.footerRight.inFooter)
        #expect(!StatusBarSettings.Position.headerLeft.inFooter)
        #expect(!StatusBarSettings.Position.headerRight.inFooter)
    }

    @Test func positionLeadingVsTrailing() {
        #expect(StatusBarSettings.Position.footerLeft.isLeading)
        #expect(StatusBarSettings.Position.headerLeft.isLeading)
        #expect(!StatusBarSettings.Position.footerRight.isLeading)
        #expect(!StatusBarSettings.Position.headerRight.isLeading)
    }

    @Test func allPositionsHaveLabels() {
        for p in StatusBarSettings.Position.allCases {
            #expect(!p.label.isEmpty)
        }
    }
}
