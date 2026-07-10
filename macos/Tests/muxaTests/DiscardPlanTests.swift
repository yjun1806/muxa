import XCTest
@testable import muxa

/// DiscardPlan 순수 계획 검증 — 파일 종류별 discard 단계가 데이터 손실 없이 구성되는지.
final class DiscardPlanTests: XCTestCase {
    func testUntrackedTrashesOnly() {
        let c = GitFileChange(path: "new.txt", index: "?", worktree: "?")
        XCTAssertEqual(DiscardPlan.steps(for: c), [.trash("new.txt")])
    }

    func testAddedFileUnstagesThenTrashes() {
        // 새로 add된 파일(A)은 HEAD에 없어 restore 불가 → 언스테이지 후 휴지통.
        let c = GitFileChange(path: "added.txt", index: "A", worktree: " ")
        XCTAssertEqual(DiscardPlan.steps(for: c), [
            .git(["restore", "--staged", "--", "added.txt"]),
            .trash("added.txt"),
        ])
    }

    func testModifiedFileRestoresIndexAndWorktree() {
        let c = GitFileChange(path: "src/a.swift", index: " ", worktree: "M")
        XCTAssertEqual(DiscardPlan.steps(for: c), [
            .git(["restore", "--staged", "--worktree", "--source=HEAD", "--", "src/a.swift"]),
        ])
    }

    func testStagedRenameHandlesBothPaths() {
        // R "old -> new": 원본·대상 모두 처리해야 old가 사라지지 않는다.
        let c = GitFileChange(path: "old.txt -> new.txt", index: "R", worktree: " ")
        XCTAssertTrue(c.isRename)
        XCTAssertEqual(c.oldPath, "old.txt")
        XCTAssertEqual(c.newPath, "new.txt")
        XCTAssertEqual(DiscardPlan.steps(for: c), [
            .git(["restore", "--staged", "--", "old.txt", "new.txt"]),
            .git(["restore", "--worktree", "--source=HEAD", "--", "old.txt"]),
            .trash("new.txt"),
        ])
    }

    func testStagedRenameWithWorktreeModStillHandlesBothPaths() {
        // RM: 인덱스 리네임 후 워크트리 추가 수정 — 계획은 index R만 보고 동일하게 안전 처리.
        let c = GitFileChange(path: "a.txt -> b.txt", index: "R", worktree: "M")
        XCTAssertEqual(DiscardPlan.steps(for: c), [
            .git(["restore", "--staged", "--", "a.txt", "b.txt"]),
            .git(["restore", "--worktree", "--source=HEAD", "--", "a.txt"]),
            .trash("b.txt"),
        ])
    }

    func testNonRenameOldPathEqualsPath() {
        let c = GitFileChange(path: "plain.txt", index: " ", worktree: "M")
        XCTAssertFalse(c.isRename)
        XCTAssertEqual(c.oldPath, "plain.txt")
        XCTAssertEqual(c.newPath, "plain.txt")
    }
}
