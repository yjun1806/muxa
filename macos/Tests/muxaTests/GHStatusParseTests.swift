import XCTest
@testable import muxa

/// GitService.parseGHStatus 순수 JSON 파싱 + CI 롤업 분류 검증.
final class GHStatusParseTests: XCTestCase {
    func testParsesNumberAndState() {
        let s = GitService.parseGHStatus(#"{"number":42,"state":"OPEN","url":"http://x"}"#)
        XCTAssertEqual(s?.prNumber, 42)
        XCTAssertEqual(s?.state, "OPEN")
        XCTAssertEqual(s?.url, "http://x")
    }

    func testMalformedIsNil() {
        XCTAssertNil(GitService.parseGHStatus("not json"))
        XCTAssertNil(GitService.parseGHStatus(#"{"state":"OPEN"}"#)) // number 없음
    }

    func testRollupClassification() {
        let json = #"""
        {"number":1,"state":"OPEN","statusCheckRollup":[
          {"status":"COMPLETED","conclusion":"SUCCESS"},
          {"status":"COMPLETED","conclusion":"FAILURE"},
          {"status":"IN_PROGRESS","conclusion":""},
          {"state":"SUCCESS"}
        ]}
        """#
        let s = GitService.parseGHStatus(json)
        XCTAssertEqual(s?.passing, 2)  // SUCCESS conclusion + SUCCESS state
        XCTAssertEqual(s?.failing, 1)  // FAILURE
        XCTAssertEqual(s?.pending, 1)  // IN_PROGRESS (status != COMPLETED)
    }

    func testRollupPrioritizesFailing() {
        let s = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 1, pending: 2)
        XCTAssertEqual(s.rollup, .failing) // 실패 우선
        let pendingOnly = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 0, pending: 2)
        XCTAssertEqual(pendingOnly.rollup, .pending)
        let passingOnly = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 0, pending: 0)
        XCTAssertEqual(passingOnly.rollup, .passing)
        let none = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 0, failing: 0, pending: 0)
        XCTAssertNil(none.rollup)
    }
}
