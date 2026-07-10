import XCTest
@testable import muxa

/// FuzzyMatch 순수 스코어링 검증 — ⌘K 랭킹의 단일 진실 원천.
final class FuzzyMatchTests: XCTestCase {
    func testEmptyQueryAlwaysMatchesWithZero() {
        XCTAssertEqual(FuzzyMatch.score(query: "", in: "anything"), 0)
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatch.score(query: "abc", in: "aXbXc"))
        XCTAssertNotNil(FuzzyMatch.score(query: "gs", in: "GitService"))
    }

    func testNonSubsequenceFails() {
        XCTAssertNil(FuzzyMatch.score(query: "xyz", in: "abc"))
        XCTAssertNil(FuzzyMatch.score(query: "cba", in: "abc")) // 순서 어긋나면 실패
    }

    func testQueryLongerThanTextFails() {
        XCTAssertNil(FuzzyMatch.score(query: "abcd", in: "abc"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.score(query: "GIT", in: "gitservice"))
        XCTAssertNotNil(FuzzyMatch.score(query: "git", in: "GITSERVICE"))
    }

    func testPrefixScoresHigherThanMidMatch() {
        let prefix = FuzzyMatch.score(query: "git", in: "gitservice")
        let mid = FuzzyMatch.score(query: "git", in: "my-gitservice")
        XCTAssertNotNil(prefix)
        XCTAssertNotNil(mid)
        XCTAssertGreaterThan(prefix!, mid!) // 맨 앞 매치가 더 높은 점수
    }

    func testContiguousScoresHigherThanScattered() {
        let contiguous = FuzzyMatch.score(query: "abc", in: "abcxyz")
        let scattered = FuzzyMatch.score(query: "abc", in: "aXbXcX")
        XCTAssertNotNil(contiguous)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(contiguous!, scattered!) // 연속 매치가 유리
    }

    func testWordBoundaryBonus() {
        // 단어 경계(구분자 뒤) 매치가 경계 아닌 매치보다 유리
        let boundary = FuzzyMatch.score(query: "s", in: "git-service")
        let nonBoundary = FuzzyMatch.score(query: "s", in: "gitservice")
        XCTAssertNotNil(boundary)
        XCTAssertNotNil(nonBoundary)
        XCTAssertGreaterThan(boundary!, nonBoundary!)
    }
}
