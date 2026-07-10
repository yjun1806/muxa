import XCTest
@testable import muxa

/// ResumeStrategy 순수 판정 검증 — 승인 게이트 모드 + 더티 여부 → 재개 전략. (D2 신뢰 경계)
final class ResumeStrategyTests: XCTestCase {
    func testOffNeverResumesEvenWhenDirty() {
        // off는 신뢰 경계 최우선 — 더티여도 자동 실행/강조로 승격하지 않는다.
        XCTAssertEqual(ResumeStrategy.decide(mode: .off, wasDirty: false), .none)
        XCTAssertEqual(ResumeStrategy.decide(mode: .off, wasDirty: true), .none)
    }

    func testAutoAlwaysAuto() {
        XCTAssertEqual(ResumeStrategy.decide(mode: .auto, wasDirty: false), .auto)
        XCTAssertEqual(ResumeStrategy.decide(mode: .auto, wasDirty: true), .auto)
    }

    func testManualCleanIsPlainManual() {
        XCTAssertEqual(ResumeStrategy.decide(mode: .manual, wasDirty: false), .manual)
    }

    func testManualDirtyIsEmphasizedButStillManual() {
        // 더티면 강조하되 자동 실행은 안 한다(manual의 신뢰 경계 유지).
        let s = ResumeStrategy.decide(mode: .manual, wasDirty: true)
        XCTAssertEqual(s, .manualDirty)
        XCTAssertFalse(s.isAuto)
    }

    func testOnlyAutoIsAuto() {
        XCTAssertTrue(ResumeStrategy.auto.isAuto)
        XCTAssertFalse(ResumeStrategy.none.isAuto)
        XCTAssertFalse(ResumeStrategy.manual.isAuto)
        XCTAssertFalse(ResumeStrategy.manualDirty.isAuto)
    }
}
