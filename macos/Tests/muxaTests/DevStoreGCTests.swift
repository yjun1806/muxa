import XCTest
@testable import muxa

/// 개발 저장소(`muxa-dev-<key>`) GC 판정 — 워크트리를 지워도 저장소가 영영 남는 유령을 막는다.
/// 파괴적 동작이라 **판정은 좁게, 보존은 넓게**(ScrollbackStore.orphans와 같은 원칙).
final class DevStoreGCTests: XCTestCase {
    private func store(_ name: String, origin: String?, ageDays: Double,
                       now: Date) -> MuxaSupportDir.DevStore {
        MuxaSupportDir.DevStore(path: "/support/\(name)", origin: origin,
                                modified: now.addingTimeInterval(-ageDays * 86_400))
    }

    private let grace: TimeInterval = 7 * 86_400

    /// 출처 워크트리가 사라졌고 유예도 지났다 — 진짜 고아다.
    func testMissingWorktreeAfterGraceIsOrphan() {
        let now = Date()
        let s = store("muxa-dev-gone-abc123", origin: "/repo/gone", ageDays: 10, now: now)
        let result = MuxaSupportDir.orphans([s], now: now, graceInterval: grace,
                                            exists: { _ in false })
        XCTAssertEqual(result, ["/support/muxa-dev-gone-abc123"])
    }

    /// 워크트리가 아직 있으면 절대 안 지운다 — 지금 쓰고 있는 개발빌드의 세션이다.
    func testExistingWorktreeIsKept() {
        let now = Date()
        let s = store("muxa-dev-live-abc123", origin: "/repo/live", ageDays: 999, now: now)
        let result = MuxaSupportDir.orphans([s], now: now, graceInterval: grace,
                                            exists: { $0 == "/repo/live" })
        XCTAssertTrue(result.isEmpty)
    }

    /// 워크트리가 없어도 **유예 안쪽이면 남긴다** — 방금 지운 워크트리를 되살릴 수도 있고,
    /// 경로가 일시적으로 안 보일 수도 있다(외장 디스크 등). 의심되면 안 지운다.
    func testMissingButRecentIsKept() {
        let now = Date()
        let s = store("muxa-dev-fresh-abc123", origin: "/repo/gone", ageDays: 1, now: now)
        let result = MuxaSupportDir.orphans([s], now: now, graceInterval: grace,
                                            exists: { _ in false })
        XCTAssertTrue(result.isEmpty)
    }

    /// 출처를 모르는 저장소는 **건드리지 않는다** — 판단 근거가 없으면 지우지 않는다
    /// (옛 버전이 만든 것이거나 사람이 손으로 넣은 것일 수 있다).
    func testUnknownOriginIsKept() {
        let now = Date()
        let s = store("muxa-dev-mystery", origin: nil, ageDays: 999, now: now)
        let result = MuxaSupportDir.orphans([s], now: now, graceInterval: grace,
                                            exists: { _ in false })
        XCTAssertTrue(result.isEmpty)
    }

    /// **릴리스 저장소(`muxa`)는 판정 대상이 아니다** — 사용자의 실사용 데이터다.
    /// (스캔이 `muxa-dev-` 접두사만 모으지만, 판정에서도 한 번 더 막는다.)
    func testReleaseStoreIsNeverOrphan() {
        let now = Date()
        let s = MuxaSupportDir.DevStore(path: "/support/muxa", origin: nil,
                                        modified: now.addingTimeInterval(-999 * 86_400))
        let result = MuxaSupportDir.orphans([s], now: now, graceInterval: grace,
                                            exists: { _ in false })
        XCTAssertTrue(result.isEmpty)
    }

    /// 자기 자신은 절대 안 지운다(지금 이 프로세스가 쓰고 있다).
    func testCurrentStoreIsKept() {
        let now = Date()
        let mine = store("muxa-dev-mine-abc123", origin: "/repo/mine", ageDays: 999, now: now)
        let result = MuxaSupportDir.orphans([mine], now: now, graceInterval: grace,
                                            exists: { _ in false }, // 워크트리가 사라진 척해도
                                            currentPath: "/support/muxa-dev-mine-abc123")
        XCTAssertTrue(result.isEmpty)
    }
}
