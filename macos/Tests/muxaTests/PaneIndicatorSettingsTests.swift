import Foundation
import Testing
@testable import muxa

/// 칸 상태 표시 설정 — 상태별(working/waiting/done) 로드/클램프/영속 + 모션 유효성. 뷰 없이 못 박는다.
struct PaneIndicatorSettingsTests {

    private func suite(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.test.paneindicator.\(name)")!
        d.removePersistentDomain(forName: "muxa.test.paneindicator.\(name)")
        return d
    }

    // MARK: - 상태별 기본값

    @Test func defaultsPerState() {
        let s = PaneIndicatorSettings(defaults: suite())
        #expect(s.working.form == .top)       // 진행중 = 상단 진행바
        #expect(s.working.motion == .flow)
        #expect(s.waiting.form == .ring)      // 대기 = 펄스 링
        #expect(s.waiting.motion == .pulse)
        #expect(s.done.form == .ring)         // 완료 = 정적 링
        #expect(s.done.motion == .none)
        #expect(!s.clearOnFocus)             // 기본 = 포커스해도 유지
    }

    @Test func everyStateHasDefaultStyleAndColor() {
        for state in PaneIndicatorState.allCases {
            #expect(!state.label.isEmpty, "\(state.rawValue) 라벨 누락")
            _ = state.color // 크래시 없이 색을 낸다
        }
    }

    // MARK: - 로드 / 클램프 / 영속

    @Test func outOfRangeStoredValuesClampOnLoad() {
        let d = suite()
        d.set(999, forKey: "muxa.paneindicator.working.thickness")
        d.set(-5, forKey: "muxa.paneindicator.working.glowSpread")
        let s = PaneIndicatorSettings(defaults: d)
        #expect(s.working.thickness == PaneIndicatorSettings.thicknessRange.upperBound)
        #expect(s.working.glowSpread == PaneIndicatorSettings.glowSpreadRange.lowerBound)
    }

    @Test func unknownFormFallsBackToStateDefault() {
        let d = suite()
        d.set("nonsense", forKey: "muxa.paneindicator.waiting.form")
        #expect(PaneIndicatorSettings(defaults: d).waiting.form == PaneIndicatorState.waiting.defaultStyle.form)
    }

    @Test func writePersistsPerStateIndependently() {
        let d = suite()
        let s = PaneIndicatorSettings(defaults: d)
        s.setStyle(PaneIndicatorStyle(form: .bracket, motion: .glow, thickness: 4,
                                      bracketInset: 10, speed: 2.4, glowSpread: 30), for: .done)
        s.clearOnFocus = true
        let reloaded = PaneIndicatorSettings(defaults: d)
        #expect(reloaded.done.form == .bracket)
        #expect(reloaded.done.motion == .glow)
        #expect(reloaded.done.thickness == 4)
        #expect(abs(reloaded.done.speed - 2.4) < 0.001) // swift-testing엔 accuracy: 대응물이 없다
        #expect(reloaded.clearOnFocus)
        // 다른 상태는 안 건드려진다.
        #expect(reloaded.working.form == PaneIndicatorState.working.defaultStyle.form)
    }

    // MARK: - 모션 resolved(형태별 유효성) — 순수 판정

    @Test func flowStaysOnBars() {
        for form in [PaneIndicatorForm.top, .bottom, .left] {
            #expect(PaneMotion.flow.resolved(for: form) == .flow, "\(form.rawValue)엔 흐름이 있어야 한다")
        }
    }

    @Test func flowFallsBackToPulseOffBars() {
        for form in [PaneIndicatorForm.ring, .bracket, .corner] {
            #expect(PaneMotion.flow.resolved(for: form) == .pulse, "\(form.rawValue)에선 흐름→펄스")
        }
    }

    @Test func nonFlowMotionsPassThroughUnchanged() {
        for motion in [PaneMotion.none, .pulse, .glow] {
            for form in PaneIndicatorForm.allCases {
                #expect(motion.resolved(for: form) == motion)
            }
        }
    }

    @Test func everyFormAndMotionHasLabel() {
        for form in PaneIndicatorForm.allCases { #expect(!form.label.isEmpty) }
        for motion in PaneMotion.allCases { #expect(!motion.label.isEmpty) }
    }
}
