import Testing
@testable import muxa

/// GitService.parseGHStatus 순수 JSON 파싱 + CI 롤업 분류 검증.
struct GHStatusParseTests {
    @Test func parsesNumberAndState() {
        let s = GitService.parseGHStatus(#"{"number":42,"state":"OPEN","url":"http://x"}"#)
        #expect(s?.prNumber == 42)
        #expect(s?.state == "OPEN")
        #expect(s?.url == "http://x")
    }

    @Test func malformedIsNil() {
        #expect(GitService.parseGHStatus("not json") == nil)
        #expect(GitService.parseGHStatus(#"{"state":"OPEN"}"#) == nil) // number 없음
    }

    @Test func rollupClassification() {
        let json = #"""
        {"number":1,"state":"OPEN","statusCheckRollup":[
          {"status":"COMPLETED","conclusion":"SUCCESS"},
          {"status":"COMPLETED","conclusion":"FAILURE"},
          {"status":"IN_PROGRESS","conclusion":""},
          {"state":"SUCCESS"}
        ]}
        """#
        let s = GitService.parseGHStatus(json)
        #expect(s?.passing == 2)  // SUCCESS conclusion + SUCCESS state
        #expect(s?.failing == 1)  // FAILURE
        #expect(s?.pending == 1)  // IN_PROGRESS (status != COMPLETED)
    }

    @Test func rollupPrioritizesFailing() {
        let s = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 1, pending: 2)
        #expect(s.rollup == .failing) // 실패 우선
        let pendingOnly = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 0, pending: 2)
        #expect(pendingOnly.rollup == .pending)
        let passingOnly = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 3, failing: 0, pending: 0)
        #expect(passingOnly.rollup == .passing)
        let none = GitService.GHStatus(prNumber: 1, state: "OPEN", url: "", passing: 0, failing: 0, pending: 0)
        #expect(none.rollup == nil)
    }
}
