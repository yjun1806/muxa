import Testing
@testable import muxa

/// GitService 순수 파싱 검증 — porcelain v1 --branch, log unit-separator 포맷.
struct GitServiceParseTests {
    @Test func testParseStatusBranchAndAheadBehind() {
        let s = GitService.parseStatus("## main...origin/main [ahead 1, behind 2]")
        #expect(s.branch == "main")
        #expect(s.ahead == 1)
        #expect(s.behind == 2)
    }

    @Test func testParseStatusBranchNoUpstream() {
        let s = GitService.parseStatus("## feature/x")
        #expect(s.branch == "feature/x")
        #expect(s.ahead == 0)
        #expect(s.behind == 0)
    }

    @Test func testParseStatusChanges() {
        let s = GitService.parseStatus("""
        ## main
         M src/a.swift
        A  src/b.swift
        ?? untracked.txt
        """)
        #expect(s.changes.count == 3)
        let modified = s.changes.first { $0.path == "src/a.swift" }
        #expect(modified?.worktree == "M")
        let untracked = s.changes.first { $0.path == "untracked.txt" }
        #expect(untracked?.isUntracked == true)
        #expect(s.staged.contains { $0.path == "src/b.swift" } == true)
    }

    @Test func testParseStatusRenameOpPath() {
        let s = GitService.parseStatus("## main\nR  old.txt -> new.txt")
        let renamed = s.changes.first
        #expect(renamed?.opPath == "new.txt") // add/restore 대상은 새 경로
    }

    @Test func testParseLogUnitSeparator() {
        let us = "\u{1f}"
        let line = ["abc123", "abc", "커밋 제목", "홍길동", "2 hours ago"].joined(separator: us)
        let commits = GitService.parseLog(line)
        #expect(commits.count == 1)
        #expect(commits[0].hash == "abc123")
        #expect(commits[0].shortHash == "abc")
        #expect(commits[0].subject == "커밋 제목")
        #expect(commits[0].author == "홍길동")
        #expect(commits[0].date == "2 hours ago")
    }

    @Test func testParseLogSkipsMalformed() {
        #expect(GitService.parseLog("only\u{1f}three\u{1f}fields").count == 0)
    }
}
