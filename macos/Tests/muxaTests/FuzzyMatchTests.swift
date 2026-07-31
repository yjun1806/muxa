import Testing
@testable import muxa

/// FuzzyMatch 순수 스코어링 검증 — ⌘K 랭킹의 단일 진실 원천.
struct FuzzyMatchTests {
    @Test func testEmptyQueryAlwaysMatchesWithZero() {
        #expect(FuzzyMatch.score(query: "", in: "anything") == 0)
    }

    @Test func testSubsequenceMatches() {
        #expect(FuzzyMatch.score(query: "abc", in: "aXbXc") != nil)
        #expect(FuzzyMatch.score(query: "gs", in: "GitService") != nil)
    }

    @Test func testNonSubsequenceFails() {
        #expect(FuzzyMatch.score(query: "xyz", in: "abc") == nil)
        #expect(FuzzyMatch.score(query: "cba", in: "abc") == nil) // 순서 어긋나면 실패
    }

    @Test func testQueryLongerThanTextFails() {
        #expect(FuzzyMatch.score(query: "abcd", in: "abc") == nil)
    }

    @Test func testCaseInsensitive() {
        #expect(FuzzyMatch.score(query: "GIT", in: "gitservice") != nil)
        #expect(FuzzyMatch.score(query: "git", in: "GITSERVICE") != nil)
    }

    @Test func testPrefixScoresHigherThanMidMatch() {
        let prefix = FuzzyMatch.score(query: "git", in: "gitservice")
        let mid = FuzzyMatch.score(query: "git", in: "my-gitservice")
        #expect(prefix != nil)
        #expect(mid != nil)
        #expect(prefix! > mid!) // 맨 앞 매치가 더 높은 점수
    }

    @Test func testContiguousScoresHigherThanScattered() {
        let contiguous = FuzzyMatch.score(query: "abc", in: "abcxyz")
        let scattered = FuzzyMatch.score(query: "abc", in: "aXbXcX")
        #expect(contiguous != nil)
        #expect(scattered != nil)
        #expect(contiguous! > scattered!) // 연속 매치가 유리
    }

    @Test func testWordBoundaryBonus() {
        // 단어 경계(구분자 뒤) 매치가 경계 아닌 매치보다 유리
        let boundary = FuzzyMatch.score(query: "s", in: "git-service")
        let nonBoundary = FuzzyMatch.score(query: "s", in: "gitservice")
        #expect(boundary != nil)
        #expect(nonBoundary != nil)
        #expect(boundary! > nonBoundary!)
    }
}
