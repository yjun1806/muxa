import XCTest
@testable import muxa

/// 소스 우선순위 — A-1이 신선하면 API를 건너뛰고(429 회피), 아니면 A-2로 넘긴다.
final class UsageSourceSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private let freshFor: TimeInterval = 600 // 10분

    private func limit(kind: String, resetsAt: Date?) -> UsageLimit {
        UsageLimit(kind: kind, label: kind, percent: 20, resetsAt: resetsAt,
                   severity: "normal", isModelScoped: false)
    }

    private func snapshot(ageSeconds: TimeInterval, resetsAt: Date?) -> UsageSourceSelector.StatusLine {
        UsageSourceSelector.StatusLine(
            observedAt: now.addingTimeInterval(-ageSeconds),
            limits: [limit(kind: "session", resetsAt: resetsAt)])
    }

    /// 신선하고 창이 유효하면 A-1 값을 쓰고 API를 건너뛴다.
    func testFreshStatusLineIsUsed() {
        let sl = snapshot(ageSeconds: 60, resetsAt: now.addingTimeInterval(3600))
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: sl, now: now, freshFor: freshFor),
                       .statusLine(sl.limits))
    }

    /// 스냅샷이 없으면(콜드스타트·미설치) API로.
    func testNilFallsBackToApi() {
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: nil, now: now, freshFor: freshFor), .api)
    }

    /// 한도가 비어 오면(첫 응답 전) API로.
    func testEmptyLimitsFallsBackToApi() {
        let sl = UsageSourceSelector.StatusLine(observedAt: now, limits: [])
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: sl, now: now, freshFor: freshFor), .api)
    }

    /// observedAt이 freshFor보다 오래되면(긴 유휴) API로 교차확인.
    func testStaleFallsBackToApi() {
        let sl = snapshot(ageSeconds: 601, resetsAt: now.addingTimeInterval(3600))
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: sl, now: now, freshFor: freshFor), .api)
    }

    /// 리셋 시각이 지난 창이 있으면(창 리셋됨, percent는 옛값) API로 실측.
    func testExpiredWindowFallsBackToApi() {
        let sl = snapshot(ageSeconds: 60, resetsAt: now.addingTimeInterval(-1))
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: sl, now: now, freshFor: freshFor), .api)
    }

    /// resets_at이 nil이어도(파싱 실패) percent는 유효 — A-1을 쓴다.
    func testNilResetIsStillUsed() {
        let sl = snapshot(ageSeconds: 60, resetsAt: nil)
        XCTAssertEqual(UsageSourceSelector.pick(statusLine: sl, now: now, freshFor: freshFor),
                       .statusLine(sl.limits))
    }
}
