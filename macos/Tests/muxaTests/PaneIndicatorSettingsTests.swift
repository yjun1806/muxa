import XCTest
@testable import muxa

/// 칸 상태 표시 설정 — 상태별(working/waiting/done) 로드/클램프/영속 + 모션 유효성. 뷰 없이 못 박는다.
final class PaneIndicatorSettingsTests: XCTestCase {

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.paneindicator.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.paneindicator.\(name)")
        return d
    }

    // MARK: - 상태별 기본값

    func testDefaultsPerState() {
        let s = PaneIndicatorSettings(defaults: suite())
        XCTAssertEqual(s.working.form, .top)       // 진행중 = 상단 진행바
        XCTAssertEqual(s.working.motion, .flow)
        XCTAssertEqual(s.waiting.form, .ring)      // 대기 = 펄스 링
        XCTAssertEqual(s.waiting.motion, .pulse)
        XCTAssertEqual(s.done.form, .ring)         // 완료 = 정적 링
        XCTAssertEqual(s.done.motion, .none)
        XCTAssertFalse(s.clearOnFocus)             // 기본 = 포커스해도 유지
    }

    func testEveryStateHasDefaultStyleAndColor() {
        for state in PaneIndicatorState.allCases {
            XCTAssertFalse(state.label.isEmpty, "\(state.rawValue) 라벨 누락")
            _ = state.color // 크래시 없이 색을 낸다
        }
    }

    // MARK: - 로드 / 클램프 / 영속

    func testOutOfRangeStoredValuesClampOnLoad() {
        let d = suite()
        d.set(999, forKey: "muxa.paneindicator.working.thickness")
        d.set(-5, forKey: "muxa.paneindicator.working.glowSpread")
        let s = PaneIndicatorSettings(defaults: d)
        XCTAssertEqual(s.working.thickness, PaneIndicatorSettings.thicknessRange.upperBound)
        XCTAssertEqual(s.working.glowSpread, PaneIndicatorSettings.glowSpreadRange.lowerBound)
    }

    func testUnknownFormFallsBackToStateDefault() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.paneindicator.waiting.form")
        XCTAssertEqual(PaneIndicatorSettings(defaults: d).waiting.form, PaneIndicatorState.waiting.defaultStyle.form)
    }

    func testWritePersistsPerStateIndependently() {
        let d = suite()
        let s = PaneIndicatorSettings(defaults: d)
        s.setStyle(PaneIndicatorStyle(form: .bracket, motion: .glow, thickness: 4,
                                      bracketInset: 10, speed: 2.4, glowSpread: 30), for: .done)
        s.clearOnFocus = true
        let reloaded = PaneIndicatorSettings(defaults: d)
        XCTAssertEqual(reloaded.done.form, .bracket)
        XCTAssertEqual(reloaded.done.motion, .glow)
        XCTAssertEqual(reloaded.done.thickness, 4)
        XCTAssertEqual(reloaded.done.speed, 2.4, accuracy: 0.001)
        XCTAssertTrue(reloaded.clearOnFocus)
        // 다른 상태는 안 건드려진다.
        XCTAssertEqual(reloaded.working.form, PaneIndicatorState.working.defaultStyle.form)
    }

    // MARK: - 모션 resolved(형태별 유효성) — 순수 판정

    func testFlowStaysOnBars() {
        for form in [PaneIndicatorForm.top, .bottom, .left] {
            XCTAssertEqual(PaneMotion.flow.resolved(for: form), .flow, "\(form.rawValue)엔 흐름이 있어야 한다")
        }
    }

    func testFlowFallsBackToPulseOffBars() {
        for form in [PaneIndicatorForm.ring, .bracket, .corner] {
            XCTAssertEqual(PaneMotion.flow.resolved(for: form), .pulse, "\(form.rawValue)에선 흐름→펄스")
        }
    }

    func testNonFlowMotionsPassThroughUnchanged() {
        for motion in [PaneMotion.none, .pulse, .glow] {
            for form in PaneIndicatorForm.allCases {
                XCTAssertEqual(motion.resolved(for: form), motion)
            }
        }
    }

    func testEveryFormAndMotionHasLabel() {
        for form in PaneIndicatorForm.allCases { XCTAssertFalse(form.label.isEmpty) }
        for motion in PaneMotion.allCases { XCTAssertFalse(motion.label.isEmpty) }
    }
}
