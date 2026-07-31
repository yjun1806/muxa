import Testing
@testable import muxa

/// ResumeStrategy 순수 판정 검증 — 승인 게이트 모드 + 더티 여부 → 재개 전략. (D2 신뢰 경계)
struct ResumeStrategyTests {
    @Test func testOffNeverResumesEvenWhenDirty() {
        // off는 신뢰 경계 최우선 — 더티여도 자동 실행/강조로 승격하지 않는다.
        #expect(ResumeStrategy.decide(mode: .off, wasDirty: false) == .none)
        #expect(ResumeStrategy.decide(mode: .off, wasDirty: true) == .none)
    }

    @Test func testAutoAlwaysAuto() {
        #expect(ResumeStrategy.decide(mode: .auto, wasDirty: false) == .auto)
        #expect(ResumeStrategy.decide(mode: .auto, wasDirty: true) == .auto)
    }

    @Test func testManualCleanIsPlainManual() {
        #expect(ResumeStrategy.decide(mode: .manual, wasDirty: false) == .manual)
    }

    @Test func testManualDirtyIsEmphasizedButStillManual() {
        // 더티면 강조하되 자동 실행은 안 한다(manual의 신뢰 경계 유지).
        let s = ResumeStrategy.decide(mode: .manual, wasDirty: true)
        #expect(s == .manualDirty)
        #expect(!(s.isAuto))
    }

    @Test func testOnlyAutoIsAuto() {
        #expect(ResumeStrategy.auto.isAuto)
        #expect(!(ResumeStrategy.none.isAuto))
        #expect(!(ResumeStrategy.manual.isAuto))
        #expect(!(ResumeStrategy.manualDirty.isAuto))
    }
}
