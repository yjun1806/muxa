import Testing
@testable import muxa

/// SideBySideDiff 순수 2열 행 재구성 검증.
struct SideBySideDiffTests {
    @Test func fileAndHunkHeaders() {
        let rows = SideBySideDiff.rows([
            "diff --git a/foo.swift b/foo.swift",
            "--- a/foo.swift",
            "+++ b/foo.swift",
            "@@ -1,1 +1,1 @@",
            " same",
        ])
        #expect(rows.first == .file("foo.swift"))
        // ---/+++ 는 삼켜지고 hunk 헤더가 나온다
        #expect(rows.contains { if case .hunk = $0 { return true } else { return false } })
    }

    @Test func contextLinePairsBothSides() {
        let rows = SideBySideDiff.rows(["@@ -5,1 +8,1 @@", " keep"])
        // hunk 시작이 old=5, new=8 → context 줄은 좌 5 / 우 8
        let pair = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }.first
        #expect(pair?.0?.lineNo == 5)
        #expect(pair?.1?.lineNo == 8)
        #expect(pair?.0?.text == "keep")
        #expect(pair?.0?.kind == .context)
    }

    @Test func delAddPairedTogether() {
        let rows = SideBySideDiff.rows(["@@ -1,1 +1,1 @@", "-old", "+new"])
        let pairs = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }
        #expect(pairs.count == 1)
        #expect(pairs[0].0?.kind == .del)
        #expect(pairs[0].0?.text == "old")
        #expect(pairs[0].1?.kind == .add)
        #expect(pairs[0].1?.text == "new")
    }

    @Test func unevenDelLeavesRightEmpty() {
        // 삭제 2 + 추가 1 → 첫 짝은 좌우, 둘째 짝은 좌만(우 nil)
        let rows = SideBySideDiff.rows(["@@ -1,2 +1,1 @@", "-a", "-b", "+c"])
        let pairs = rows.compactMap { row -> (SideBySideDiff.Cell?, SideBySideDiff.Cell?)? in
            if case .pair(let l, let r) = row { return (l, r) } else { return nil }
        }
        #expect(pairs.count == 2)
        #expect(pairs[1].0 != nil)   // 남는 삭제는 좌측
        #expect(pairs[1].1 == nil)       // 우측은 빈다
    }
}
