import Testing
@testable import muxa

/// ReviewCommentAnchor 순수 재앵커링 검증 — 라이브 리로드 diff에서 코멘트 드리프트 방지.
struct ReviewCommentAnchorTests {
    @Test func hunkStarts() {
        #expect(ReviewCommentAnchor.hunkStarts("@@ -1,2 +3,4 @@")?.old == 1)
        #expect(ReviewCommentAnchor.hunkStarts("@@ -1,2 +3,4 @@")?.new == 3)
        #expect(ReviewCommentAnchor.hunkStarts("@@ -5 +8 @@")?.new == 8) // 카운트 생략형
        #expect(ReviewCommentAnchor.hunkStarts("not a hunk") == nil)
    }

    @Test func filePathFromDiffHeader() {
        #expect(ReviewCommentAnchor.filePath(fromDiffHeader: "diff --git a/src/x.swift b/src/x.swift") == "src/x.swift")
        #expect(ReviewCommentAnchor.filePath(fromPlusHeader: "+++ b/src/y.swift") == "src/y.swift")
        #expect(ReviewCommentAnchor.filePath(fromPlusHeader: "+++ /dev/null") == nil)
    }

    private let diff = [
        "diff --git a/foo.txt b/foo.txt",
        "--- a/foo.txt",
        "+++ b/foo.txt",
        "@@ -1,3 +1,3 @@",
        " keep",
        "-removed",
        "+added",
        " tail",
    ]

    @Test func resolveAnchoredWhenUnchanged() {
        // added는 new 줄번호 2(keep=1, added=2)
        let c = ReviewComment(file: "foo.txt", side: .add, line: 2, lineText: "added", body: "hi", seq: 0)
        let out = ReviewCommentAnchor.resolve([c], lines: diff)
        #expect(out.first?.status == .anchored)
        #expect(out.first?.resolvedLine == 2)
    }

    @Test func resolveMovedWhenLineShifted() {
        // 저장 당시 줄번호는 99였지만 텍스트 "added"가 diff 안에 유일 → moved로 실제 줄(2)로 이동
        let c = ReviewComment(file: "foo.txt", side: .add, line: 99, lineText: "added", body: "hi", seq: 0)
        let out = ReviewCommentAnchor.resolve([c], lines: diff)
        #expect(out.first?.status == .moved)
        #expect(out.first?.resolvedLine == 2)
    }

    @Test func resolveOutdatedWhenTextGone() {
        let c = ReviewComment(file: "foo.txt", side: .add, line: 2, lineText: "nonexistent", body: "hi", seq: 0)
        let out = ReviewCommentAnchor.resolve([c], lines: diff)
        #expect(out.first?.status == .outdated)
        #expect(out.first?.resolvedLine == nil)
    }

    @Test func resolveOutdatedWhenAmbiguous() {
        // 같은 텍스트가 둘 이상이면 위치 불명 → outdated
        let dup = ["diff --git a/d.txt b/d.txt", "--- a/d.txt", "+++ b/d.txt", "@@ -1,2 +1,2 @@", "+dup", "+dup"]
        let c = ReviewComment(file: "d.txt", side: .add, line: 50, lineText: "dup", body: "hi", seq: 0)
        #expect(ReviewCommentAnchor.resolve([c], lines: dup).first?.status == .outdated)
    }
}
