import XCTest
@testable import muxa

/// GitService 순수 파싱 검증 — porcelain v1 --branch, log unit-separator 포맷.
final class GitServiceParseTests: XCTestCase {
    func testParseStatusBranchAndAheadBehind() {
        let s = GitService.parseStatus("## main...origin/main [ahead 1, behind 2]")
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.ahead, 1)
        XCTAssertEqual(s.behind, 2)
    }

    func testParseStatusBranchNoUpstream() {
        let s = GitService.parseStatus("## feature/x")
        XCTAssertEqual(s.branch, "feature/x")
        XCTAssertEqual(s.ahead, 0)
        XCTAssertEqual(s.behind, 0)
    }

    func testParseStatusChanges() {
        let s = GitService.parseStatus("""
        ## main
         M src/a.swift
        A  src/b.swift
        ?? untracked.txt
        """)
        XCTAssertEqual(s.changes.count, 3)
        let modified = s.changes.first { $0.path == "src/a.swift" }
        XCTAssertEqual(modified?.worktree, "M")
        let untracked = s.changes.first { $0.path == "untracked.txt" }
        XCTAssertEqual(untracked?.isUntracked, true)
        XCTAssertEqual(s.staged.contains { $0.path == "src/b.swift" }, true)
    }

    func testParseStatusRenameOpPath() {
        let s = GitService.parseStatus("## main\nR  old.txt -> new.txt")
        let renamed = s.changes.first
        XCTAssertEqual(renamed?.opPath, "new.txt") // add/restore 대상은 새 경로
    }

    func testParseLogUnitSeparator() {
        let us = "\u{1f}"
        let line = ["abc123", "abc", "커밋 제목", "홍길동", "2 hours ago"].joined(separator: us)
        let commits = GitService.parseLog(line)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].hash, "abc123")
        XCTAssertEqual(commits[0].shortHash, "abc")
        XCTAssertEqual(commits[0].subject, "커밋 제목")
        XCTAssertEqual(commits[0].author, "홍길동")
        XCTAssertEqual(commits[0].date, "2 hours ago")
    }

    func testParseLogSkipsMalformed() {
        XCTAssertEqual(GitService.parseLog("only\u{1f}three\u{1f}fields").count, 0)
    }
}
