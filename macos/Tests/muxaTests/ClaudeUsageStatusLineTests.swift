import XCTest
@testable import muxa

/// A-1 경로 파싱 — Claude Code statusLine stdin의 `rate_limits`를 UsageLimit로 정규화한다.
/// A-2(`/api/oauth/usage`)와 스키마가 달라 별도 파서다. 뷰가 출처를 모르게 같은 타입으로 맞춘다.
final class ClaudeUsageStatusLineTests: XCTestCase {
    private func parse(_ json: String) -> [UsageLimit] {
        ClaudeUsage.parseStatusLine(Data(json.utf8))
    }

    /// 두 창이 다 오면 session·weekly_all 두 한도로 정규화된다.
    func testParsesBothWindows() {
        let limits = parse("""
        { "rate_limits": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1770000000 },
            "seven_day": { "used_percentage": 40, "resets_at": 1770500000 }
        } }
        """)
        XCTAssertEqual(limits.count, 2)
        let session = limits.first { $0.kind == "session" }
        XCTAssertEqual(session?.label, "5h")
        XCTAssertEqual(session?.percent, 24) // 23.5 반올림
        XCTAssertEqual(session?.resetsAt, Date(timeIntervalSince1970: 1770000000))
        XCTAssertFalse(session?.isModelScoped ?? true)
        XCTAssertEqual(limits.first { $0.kind == "weekly_all" }?.label, "wk")
    }

    /// 창은 독립적으로 없을 수 있다 — five_hour만 오면 그것만 나온다.
    func testMissingWindowIsOmitted() {
        let limits = parse("""
        { "rate_limits": { "five_hour": { "used_percentage": 10, "resets_at": 1770000000 } } }
        """)
        XCTAssertEqual(limits.map(\.kind), ["session"])
    }

    /// rate_limits 자체가 없으면(콜드스타트·API키 사용자) 빈 배열 — 앱 동작에 영향 없다.
    func testNoRateLimitsYieldsEmpty() {
        XCTAssertTrue(parse("""
        { "session_id": "abc", "cost": { "total_cost_usd": 0.1 } }
        """).isEmpty)
    }

    /// used_percentage가 없는 창은 버린다(부분 응답 방어).
    func testWindowWithoutPercentIsDropped() {
        let limits = parse("""
        { "rate_limits": {
            "five_hour": { "resets_at": 1770000000 },
            "seven_day": { "used_percentage": 5, "resets_at": 1770500000 }
        } }
        """)
        XCTAssertEqual(limits.map(\.kind), ["weekly_all"])
    }

    /// resets_at이 없어도 percent는 살린다(리셋 시각만 nil).
    func testWindowWithoutResetKeepsPercent() {
        let limits = parse("""
        { "rate_limits": { "five_hour": { "used_percentage": 55 } } }
        """)
        XCTAssertEqual(limits.first?.percent, 55)
        XCTAssertNil(limits.first?.resetsAt)
    }

    /// 깨진 JSON도 조용히 빈 배열 — 비공식 stdin이라 실패를 정상 경로로 취급한다.
    func testMalformedYieldsEmpty() {
        XCTAssertTrue(parse("not json at all").isEmpty)
    }
}
