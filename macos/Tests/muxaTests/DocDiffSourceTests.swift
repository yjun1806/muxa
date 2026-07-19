import XCTest
@testable import muxa

/// 문서 diff 출처 판정 — 어느 쪽을 어디서 읽을지. 틀리면 diff가 통째로 초록/빨강이 된다.
final class DocDiffSourceTests: XCTestCase {

    private func change(_ path: String, index: Character = " ", worktree: Character = "M") -> GitFileChange {
        GitFileChange(path: path, index: index, worktree: worktree)
    }

    // MARK: 미커밋 파일

    func testModifiedFileReadsHeadAndWorktree() {
        let s = DocDiffSource.resolve(.file(change("docs/DESIGN.md")))
        XCTAssertEqual(s?.old, .revision(rev: "HEAD", path: "docs/DESIGN.md"))
        XCTAssertEqual(s?.new, .worktree(path: "docs/DESIGN.md"))
    }

    /// 추적 안 된 파일은 옛쪽이 없다 — HEAD를 읽으려 하면 실패한다.
    func testUntrackedHasEmptyOldSide() {
        let s = DocDiffSource.resolve(.file(change("new.md", index: "?", worktree: "?")))
        XCTAssertEqual(s?.old, .empty)
        XCTAssertEqual(s?.new, .worktree(path: "new.md"))
    }

    /// 삭제된 파일은 새쪽이 없다 — 디스크를 읽으면 "파일 없음"이 된다.
    func testDeletedHasEmptyNewSide() {
        let s = DocDiffSource.resolve(.file(change("gone.md", index: "D", worktree: " ")))
        XCTAssertEqual(s?.old, .revision(rev: "HEAD", path: "gone.md"))
        XCTAssertEqual(s?.new, .empty)
    }

    /// **리네임은 옛 경로로 읽어야 한다** — 새 경로는 옛 리비전에 없다.
    func testRenameReadsOldPathFromHead() {
        let s = DocDiffSource.resolve(.file(change("old.md -> new.md", index: "R", worktree: " ")))
        XCTAssertEqual(s?.old, .revision(rev: "HEAD", path: "old.md"))
        XCTAssertEqual(s?.new, .worktree(path: "new.md"))
    }

    // MARK: 커밋 안 파일

    /// 양쪽 다 리비전 — **디스크를 안 본다.** 원본이 지워졌어도 문서 diff가 된다.
    func testCommitFileReadsBothRevisions() {
        let s = DocDiffSource.resolve(.commitFile(hash: "abc123", path: "docs/A.md"))
        XCTAssertEqual(s?.old, .revision(rev: "abc123^", path: "docs/A.md"))
        XCTAssertEqual(s?.new, .revision(rev: "abc123", path: "docs/A.md"))
    }

    func testCommitFileRenameUsesOldPathForParent() {
        let s = DocDiffSource.resolve(.commitFile(hash: "abc123", path: "new.md", oldPath: "old.md"))
        XCTAssertEqual(s?.old, .revision(rev: "abc123^", path: "old.md"))
        XCTAssertEqual(s?.new, .revision(rev: "abc123", path: "new.md"))
    }

    // MARK: 집계 diff는 대상 아님

    func testAggregateTargetsHaveNoSource() {
        XCTAssertNil(DocDiffSource.resolve(.commit(hash: "abc", subject: "s")))
        XCTAssertNil(DocDiffSource.resolve(.all(base: nil)))
    }
}

/// 보기 모드 가용성 — 안 되는 버튼을 그리지 않기 위한 판정.
final class ChangesViewModeTests: XCTestCase {

    private func mdChange() -> GitDiffTarget { .file(GitFileChange(path: "a.md", index: " ", worktree: "M")) }
    private func swiftChange() -> GitDiffTarget { .file(GitFileChange(path: "a.swift", index: " ", worktree: "M")) }

    /// 통합·나란히는 **언제나** 가능하다 — 모든 것의 폴백이다.
    func testUnifiedAndSideBySideAlwaysAvailable() {
        for t: GitDiffTarget in [mdChange(), swiftChange(), .all(base: nil), .commit(hash: "a", subject: "s")] {
            let modes = ChangesViewMode.available(for: t)
            XCTAssertTrue(modes.contains(.unified), "통합이 빠졌다: \(t.id)")
            XCTAssertTrue(modes.contains(.sideBySide), "나란히가 빠졌다: \(t.id)")
        }
    }

    func testDocumentOnlyForMarkdown() {
        XCTAssertTrue(ChangesViewMode.available(for: mdChange()).contains(.document))
        XCTAssertFalse(ChangesViewMode.available(for: swiftChange()).contains(.document))
    }

    /// 집계 diff는 md여도 문서 모드가 없다 — 여러 문서를 세로로 잇는 건 별개 문제다.
    func testAggregateHasNoDocumentMode() {
        XCTAssertFalse(ChangesViewMode.available(for: .commit(hash: "a", subject: "s")).contains(.document))
        XCTAssertFalse(ChangesViewMode.available(for: .all(base: nil)).contains(.document))
    }

    func testCommitFileMarkdownSupportsDocument() {
        XCTAssertTrue(ChangesViewMode.supportsDocument(.commitFile(hash: "a", path: "docs/x.md")))
        XCTAssertFalse(ChangesViewMode.supportsDocument(.commitFile(hash: "a", path: "src/x.ts")))
    }

    /// 확장자 집합이 파일 뷰어와 어긋나면 같은 파일이 화면마다 다르게 취급된다.
    func testMarkdownExtensionsMatchFileViewer() {
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn"] {
            XCTAssertTrue(ChangesViewMode.isMarkdown("a.\(ext)"), ".\(ext)가 md로 안 잡힌다")
        }
        XCTAssertFalse(ChangesViewMode.isMarkdown("a.txt"))
    }
}
