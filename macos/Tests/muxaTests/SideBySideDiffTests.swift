import XCTest
@testable import muxa

/// SideBySideDiff 순수 2열 행 재구성 검증.
final class SideBySideDiffTests: XCTestCase {
    func testFileAndHunkHeaders() {
        let rows = SideBySideDiff.rows([
            "diff --git a/foo.swift b/foo.swift",
            "--- a/foo.swift",
            "+++ b/foo.swift",
            "@@ -1,1 +1,1 @@",
            " same",
        ])
        XCTAssertEqual(rows.first, .file("foo.swift"))
        // ---/+++ 는 삼켜지고 hunk 헤더가 나온다
        XCTAssertTrue(rows.contains { if case .hunk = $0 { return true } else { return false } })
    }

    func testContextLinePairsBothSides() {
        let rows = SideBySideDiff.rows(["@@ -5,1 +8,1 @@", " keep"])
        // hunk 시작이 old=5, new=8 → context 줄은 좌 5 / 우 8
        let pair = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }.first
        XCTAssertEqual(pair?.0?.lineNo, 5)
        XCTAssertEqual(pair?.1?.lineNo, 8)
        XCTAssertEqual(pair?.0?.text, "keep")
        XCTAssertEqual(pair?.0?.kind, .context)
    }

    func testDelAddPairedTogether() {
        let rows = SideBySideDiff.rows(["@@ -1,1 +1,1 @@", "-old", "+new"])
        let pairs = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0?.kind, .del)
        XCTAssertEqual(pairs[0].0?.text, "old")
        XCTAssertEqual(pairs[0].1?.kind, .add)
        XCTAssertEqual(pairs[0].1?.text, "new")
    }

    func testUnevenDelLeavesRightEmpty() {
        // 삭제 2 + 추가 1 → 첫 짝은 좌우, 둘째 짝은 좌만(우 nil)
        let rows = SideBySideDiff.rows(["@@ -1,2 +1,1 @@", "-a", "-b", "+c"])
        let pairs = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }
        XCTAssertEqual(pairs.count, 2)
        XCTAssertNotNil(pairs[1].0)   // 남는 삭제는 좌측
        XCTAssertNil(pairs[1].1)       // 우측은 빈다
    }
}
