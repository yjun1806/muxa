import Testing
@testable import muxa

/// 문서 diff 출처 판정 — 어느 쪽을 어디서 읽을지. 틀리면 diff가 통째로 초록/빨강이 된다.
struct DocDiffSourceTests {

    private func change(_ path: String, index: Character = " ", worktree: Character = "M") -> GitFileChange {
        GitFileChange(path: path, index: index, worktree: worktree)
    }

    // MARK: 미커밋 파일

    @Test func modifiedFileReadsHeadAndWorktree() {
        let s = DocDiffSource.resolve(.file(change("docs/DESIGN.md")))
        #expect(s?.old == .revision(rev: "HEAD", path: "docs/DESIGN.md"))
        #expect(s?.new == .worktree(path: "docs/DESIGN.md"))
    }

    /// 추적 안 된 파일은 옛쪽이 없다 — HEAD를 읽으려 하면 실패한다.
    @Test func untrackedHasEmptyOldSide() {
        let s = DocDiffSource.resolve(.file(change("new.md", index: "?", worktree: "?")))
        #expect(s?.old == .empty)
        #expect(s?.new == .worktree(path: "new.md"))
    }

    /// 삭제된 파일은 새쪽이 없다 — 디스크를 읽으면 "파일 없음"이 된다.
    @Test func deletedHasEmptyNewSide() {
        let s = DocDiffSource.resolve(.file(change("gone.md", index: "D", worktree: " ")))
        #expect(s?.old == .revision(rev: "HEAD", path: "gone.md"))
        #expect(s?.new == .empty)
    }

    /// **리네임은 옛 경로로 읽어야 한다** — 새 경로는 옛 리비전에 없다.
    @Test func renameReadsOldPathFromHead() {
        let s = DocDiffSource.resolve(.file(change("old.md -> new.md", index: "R", worktree: " ")))
        #expect(s?.old == .revision(rev: "HEAD", path: "old.md"))
        #expect(s?.new == .worktree(path: "new.md"))
    }

    // MARK: 커밋 안 파일

    /// 양쪽 다 리비전 — **디스크를 안 본다.** 원본이 지워졌어도 문서 diff가 된다.
    @Test func commitFileReadsBothRevisions() {
        let s = DocDiffSource.resolve(.commitFile(hash: "abc123", path: "docs/A.md"))
        #expect(s?.old == .revision(rev: "abc123^", path: "docs/A.md"))
        #expect(s?.new == .revision(rev: "abc123", path: "docs/A.md"))
    }

    @Test func commitFileRenameUsesOldPathForParent() {
        let s = DocDiffSource.resolve(.commitFile(hash: "abc123", path: "new.md", oldPath: "old.md"))
        #expect(s?.old == .revision(rev: "abc123^", path: "old.md"))
        #expect(s?.new == .revision(rev: "abc123", path: "new.md"))
    }

    // MARK: 집계 diff는 대상 아님

    @Test func aggregateTargetsHaveNoSource() {
        #expect(DocDiffSource.resolve(.commit(hash: "abc", subject: "s")) == nil)
        #expect(DocDiffSource.resolve(.all(base: nil)) == nil)
    }
}

/// 보기 모드 가용성 — 안 되는 버튼을 그리지 않기 위한 판정.
struct ChangesViewModeTests {

    private func mdChange() -> GitDiffTarget { .file(GitFileChange(path: "a.md", index: " ", worktree: "M")) }
    private func swiftChange() -> GitDiffTarget { .file(GitFileChange(path: "a.swift", index: " ", worktree: "M")) }

    /// 통합·나란히는 **언제나** 가능하다 — 모든 것의 폴백이다.
    @Test func unifiedAndSideBySideAlwaysAvailable() {
        for t: GitDiffTarget in [mdChange(), swiftChange(), .all(base: nil), .commit(hash: "a", subject: "s")] {
            let modes = ChangesViewMode.available(for: t)
            #expect(modes.contains(.unified), "통합이 빠졌다: \(t.id)")
            #expect(modes.contains(.sideBySide), "나란히가 빠졌다: \(t.id)")
        }
    }

    @Test func documentOnlyForMarkdown() {
        #expect(ChangesViewMode.available(for: mdChange()).contains(.document))
        #expect(!(ChangesViewMode.available(for: swiftChange()).contains(.document)))
    }

    /// 집계 diff는 md여도 문서 모드가 없다 — 여러 문서를 세로로 잇는 건 별개 문제다.
    @Test func aggregateHasNoDocumentMode() {
        #expect(!(ChangesViewMode.available(for: .commit(hash: "a", subject: "s")).contains(.document)))
        #expect(!(ChangesViewMode.available(for: .all(base: nil)).contains(.document)))
    }

    @Test func commitFileMarkdownSupportsDocument() {
        #expect(ChangesViewMode.supportsDocument(.commitFile(hash: "a", path: "docs/x.md")))
        #expect(!(ChangesViewMode.supportsDocument(.commitFile(hash: "a", path: "src/x.ts"))))
    }

    /// 확장자 집합이 파일 뷰어와 어긋나면 같은 파일이 화면마다 다르게 취급된다.
    @Test func markdownExtensionsMatchFileViewer() {
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn"] {
            #expect(ChangesViewMode.isMarkdown("a.\(ext)"), ".\(ext)가 md로 안 잡힌다")
        }
        #expect(!(ChangesViewMode.isMarkdown("a.txt")))
    }
}
