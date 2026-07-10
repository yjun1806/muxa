import XCTest
@testable import muxa

/// DiffPatch 순수 분해·패치 구성 검증 — hunk 단위 스테이지의 기반.
final class DiffPatchTests: XCTestCase {
    // 실제 tracked 파일 diff(--- / +++ 헤더 있음, hunk 2개)
    private let tracked = [
        "diff --git a/foo.txt b/foo.txt",
        "index 111..222 100644",
        "--- a/foo.txt",
        "+++ b/foo.txt",
        "@@ -1,2 +1,2 @@",
        " context",
        "-old line",
        "+new line",
        "@@ -10,1 +10,2 @@",
        " keep",
        "+added",
    ]

    func testParseSeparatesHeaderAndHunks() {
        let p = DiffPatch.parse(tracked)
        XCTAssertEqual(p.header.count, 4) // diff/index/---/+++
        XCTAssertEqual(p.hunks.count, 2)
        XCTAssertTrue(p.hunks[0][0].hasPrefix("@@"))
        XCTAssertTrue(p.hunks[1][0].hasPrefix("@@"))
    }

    func testHunkCount() {
        XCTAssertEqual(DiffPatch.hunkCount(tracked), 2)
        XCTAssertEqual(DiffPatch.hunkCount(["no hunks here"]), 0)
    }

    func testHeaderIsApplicable() {
        XCTAssertTrue(DiffPatch.headerIsApplicable(["--- a/x", "+++ b/x"]))
        XCTAssertFalse(DiffPatch.headerIsApplicable(["diff --git a/x b/x"])) // ---/+++ 없음
    }

    func testPatchForHunkBuildsApplicablePatch() {
        let p = DiffPatch.parse(tracked)
        let patch = DiffPatch.patch(forHunk: 0, in: p)
        XCTAssertNotNil(patch)
        XCTAssertTrue(patch!.hasSuffix("\n"))
        XCTAssertTrue(patch!.contains("--- a/foo.txt"))
        XCTAssertTrue(patch!.contains("+new line"))
        XCTAssertFalse(patch!.contains("+added")) // 다른 hunk는 포함 안 됨
    }

    func testPatchOutOfRangeIsNil() {
        let p = DiffPatch.parse(tracked)
        XCTAssertNil(DiffPatch.patch(forHunk: 5, in: p))
    }

    func testUntrackedDiffIsNotApplicable() {
        // --no-index(untracked) diff는 --- a// +++ b/ 헤더가 없어 스테이지 불가.
        let untracked = ["diff --git a/new.txt b/new.txt", "new file mode 100644", "@@ -0,0 +1 @@", "+hello"]
        let p = DiffPatch.parse(untracked)
        XCTAssertNil(DiffPatch.patch(forHunk: 0, in: p))
    }
}
