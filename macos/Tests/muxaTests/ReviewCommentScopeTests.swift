import XCTest
@testable import muxa

/// 리뷰 코멘트의 **커밋 스코프** — 지시문에 해시가 실리는지, 구 저장분이 살아남는지.
///
/// 스코프가 없던 시절엔 커밋 diff에 단 코멘트가 같은 파일·같은 줄 내용이라는 이유로
/// **워크트리 diff에도 떠올랐다**(스토어는 리포 루트로만 키를 잡고, 재앵커링은 file+side+lineText만 본다).
final class ReviewCommentScopeTests: XCTestCase {

    private func comment(_ body: String, file: String = "a.swift", line: Int = 10,
                         seq: Int = 0, commit: String? = nil) -> ReviewComment {
        ReviewComment(file: file, side: .add, line: line, lineText: "let x = 1",
                      body: body, seq: seq, commit: commit)
    }

    /// 커밋 코멘트는 해시를 지시문에 싣는다 — 에이전트가 amend·fixup 대상을 스스로 판단하게.
    func testInstructionCarriesCommitHash() {
        let text = ReviewCommentFormat.instruction([comment("이름 바꿔", commit: "a3f9c2b1d4e5")])
        XCTAssertTrue(text.contains("a3f9c2b"), "짧은 해시가 들어가야 한다: \(text)")
        XCTAssertTrue(text.contains("이름 바꿔"))
    }

    /// 워크트리 코멘트만 있으면 스코프 머리글은 소음이라 안 붙인다.
    func testWorktreeOnlyHasNoScopeHeader() {
        let text = ReviewCommentFormat.instruction([comment("고쳐")])
        XCTAssertFalse(text.contains("==="), "스코프가 하나면 머리글을 안 붙인다: \(text)")
    }

    /// 섞여 있으면 갈라서 보여준다 — 어느 게 커밋 수정이고 어느 게 미커밋인지.
    func testMixedScopesAreSeparated() {
        let text = ReviewCommentFormat.instruction([
            comment("미커밋 것", seq: 0),
            comment("커밋 것", seq: 1, commit: "abc1234def"),
        ])
        XCTAssertTrue(text.contains("아직 커밋 안 된 변경"))
        XCTAssertTrue(text.contains("abc1234"))
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(ReviewCommentFormat.instruction([]), "")
    }

    /// **하위호환** — commit 필드가 없던 저장분이 그대로 디코드되고 워크트리 코멘트로 읽힌다.
    func testLegacyCommentDecodesWithoutCommitField() throws {
        let legacy = """
        [{"id":"1","file":"a.swift","side":"add","line":3,"lineText":"x",
          "body":"고쳐","seq":0,"createdAt":760000000}]
        """
        let decoded = try JSONDecoder().decode([ReviewComment].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].commit, "구 저장분은 워크트리 코멘트다")
    }

    func testCommentRoundTripsWithCommit() throws {
        let original = comment("고쳐", commit: "deadbeef")
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ReviewComment].self, from: data)
        XCTAssertEqual(decoded[0].commit, "deadbeef")
    }
}
