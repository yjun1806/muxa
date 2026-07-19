import XCTest
@testable import muxa

/// 커밋 파일 목록 파싱 — 실제 `git show` 출력을 그대로 넣어 검증한다.
/// 픽스처는 이 리포에서 실측한 것이다(리네임 유사도·머지 결합 diff·바이너리 모두 실물).
final class GitCommitFileTests: XCTestCase {

    // MARK: name-status

    func testBasicStatuses() {
        let files = GitCommitFileParse.parseNameStatus("M\tREADME.md\nA\tnew.swift\nD\told.swift")
        XCTAssertEqual(files.map(\.status), ["M", "A", "D"])
        XCTAssertEqual(files.map(\.path), ["README.md", "new.swift", "old.swift"])
        XCTAssertTrue(files.allSatisfy { $0.oldPath == nil })
    }

    /// 리네임은 유사도 점수가 붙고 경로가 둘이다 — 새 경로가 path, 옛 경로가 oldPath.
    func testRenameSplitsPaths() {
        let files = GitCommitFileParse.parseNameStatus("R060\tsrc/TopBar.tsx\tsrc/ContentHeader.tsx")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].status, "R")
        XCTAssertEqual(files[0].path, "src/ContentHeader.tsx")
        XCTAssertEqual(files[0].oldPath, "src/TopBar.tsx")
    }

    func testCopyBehavesLikeRename() {
        let files = GitCommitFileParse.parseNameStatus("C100\ta.swift\tb.swift")
        XCTAssertEqual(files[0].status, "C")
        XCTAssertEqual(files[0].path, "b.swift")
        XCTAssertEqual(files[0].oldPath, "a.swift")
    }

    /// 머지 커밋의 결합 diff는 부모 수만큼 상태 문자가 붙는다(`MM`) — 첫 글자만 쓴다.
    func testMergeCombinedStatusTakesFirstChar() {
        let files = GitCommitFileParse.parseNameStatus("MM\tdocs/DESIGN.md")
        XCTAssertEqual(files[0].status, "M")
        XCTAssertEqual(files[0].path, "docs/DESIGN.md")
    }

    /// 머지 커밋(파일 내역 없음)·빈 커밋 → 빈 배열. 크래시도 지어낸 항목도 없다.
    func testEmptyOutput() {
        XCTAssertTrue(GitCommitFileParse.parseNameStatus("").isEmpty)
        XCTAssertTrue(GitCommitFileParse.parseNameStatus("\n\n").isEmpty)
    }

    func testTypeChange() {
        let files = GitCommitFileParse.parseNameStatus("T\tscripts/hook.sh")
        XCTAssertEqual(files[0].status, "T")
    }

    /// 한글 경로 — `core.quotepath=false` 전제(GitService.gitArgs가 항상 붙인다).
    func testKoreanPath() {
        let files = GitCommitFileParse.parseNameStatus("M\tdocs/한글 문서.md")
        XCTAssertEqual(files[0].path, "docs/한글 문서.md")
    }

    func testPathWithSpaces() {
        let files = GitCommitFileParse.parseNameStatus("A\tmy folder/some file.txt")
        XCTAssertEqual(files[0].path, "my folder/some file.txt")
    }

    // MARK: numstat

    func testNumstatNumbers() {
        let stats = GitCommitFileParse.parseNumstat("133\t23\tREADME.md")
        XCTAssertEqual(stats["README.md"]?.added, 133)
        XCTAssertEqual(stats["README.md"]?.deleted, 23)
        XCTAssertEqual(stats["README.md"]?.binary, false)
    }

    /// 바이너리는 `-  -` — 0이 아니라 **모름**이다(0은 "안 바뀜"이라는 다른 사실).
    func testNumstatBinaryIsUnknownNotZero() {
        let stats = GitCommitFileParse.parseNumstat("-\t-\tdocs/assets/real-git.png")
        let s = stats["docs/assets/real-git.png"]
        XCTAssertEqual(s?.binary, true)
        XCTAssertNil(s?.added)
        XCTAssertNil(s?.deleted)
    }

    func testNumstatZeroIsNotNil() {
        let stats = GitCommitFileParse.parseNumstat("0\t0\tuntouched.txt")
        XCTAssertEqual(stats["untouched.txt"]?.added, 0)
        XCTAssertEqual(stats["untouched.txt"]?.deleted, 0)
    }

    // MARK: 리네임 경로 펴기

    func testExpandBraceRename() {
        XCTAssertEqual(GitCommitFileParse.expandRenamePath("src/{TopBar.tsx => ContentHeader.tsx}"),
                       "src/ContentHeader.tsx")
    }

    func testExpandBraceInDirectory() {
        XCTAssertEqual(GitCommitFileParse.expandRenamePath("{old => new}/file.swift"),
                       "new/file.swift")
    }

    func testExpandBareRename() {
        XCTAssertEqual(GitCommitFileParse.expandRenamePath("a.txt => b.txt"), "b.txt")
    }

    func testExpandLeavesPlainPath() {
        XCTAssertEqual(GitCommitFileParse.expandRenamePath("src/App.tsx"), "src/App.tsx")
    }

    /// 경로에 `{`가 있어도 화살표가 없으면 리네임이 아니다 — 건드리지 않는다.
    func testExpandIgnoresBracesWithoutArrow() {
        XCTAssertEqual(GitCommitFileParse.expandRenamePath("src/{id}/page.tsx"), "src/{id}/page.tsx")
    }

    // MARK: 합치기

    func testMergeJoinsStatsByPath() {
        let files = GitCommitFileParse.merge(
            nameStatus: "M\tREADME.md\nA\tdocs/new.md",
            numstat: "133\t23\tREADME.md\n10\t0\tdocs/new.md")
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].added, 133)
        XCTAssertEqual(files[0].deleted, 23)
        XCTAssertEqual(files[1].added, 10)
    }

    /// 리네임은 numstat이 경로를 압축해 내보낸다 — 펴서 이어야 짝이 맞는다.
    func testMergeJoinsRenameAcrossCompressedPath() {
        let files = GitCommitFileParse.merge(
            nameStatus: "R060\tsrc/TopBar.tsx\tsrc/ContentHeader.tsx",
            numstat: "5\t6\tsrc/{TopBar.tsx => ContentHeader.tsx}")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "src/ContentHeader.tsx")
        XCTAssertEqual(files[0].oldPath, "src/TopBar.tsx")
        XCTAssertEqual(files[0].added, 5)
        XCTAssertEqual(files[0].deleted, 6)
    }

    /// **머지 커밋 비대칭** — name-status와 numstat의 줄 수가 다르다(실측 3 vs 15).
    /// 순서로 짝지으면 엉뚱한 숫자가 붙는다. 경로로 잇고, 짝이 없으면 침묵한다.
    func testMergeAsymmetryDoesNotMisalign() {
        let files = GitCommitFileParse.merge(
            nameStatus: "MM\tdocs/DESIGN.md\nMM\tdocs/STATUS.md",
            numstat: "7\t0\tdocs/DESIGN.md\n27\t0\tdocs/STATUS.md\n35\t0\tsrc/Other.swift")
        XCTAssertEqual(files.count, 2, "기준 목록은 name-status다 — numstat 여분이 항목을 늘리지 않는다")
        XCTAssertEqual(files[0].path, "docs/DESIGN.md")
        XCTAssertEqual(files[0].added, 7)
        XCTAssertEqual(files[1].path, "docs/STATUS.md")
        XCTAssertEqual(files[1].added, 27)
    }

    /// 짝이 없으면 0을 지어내지 않는다.
    func testMergeKeepsStatsNilWhenUnmatched() {
        let files = GitCommitFileParse.merge(nameStatus: "M\tghost.swift", numstat: "")
        XCTAssertEqual(files.count, 1)
        XCTAssertNil(files[0].added)
        XCTAssertNil(files[0].deleted)
        XCTAssertFalse(files[0].isBinary)
    }

    func testMergeCarriesBinaryFlag() {
        let files = GitCommitFileParse.merge(
            nameStatus: "A\tdocs/assets/real-git.png",
            numstat: "-\t-\tdocs/assets/real-git.png")
        XCTAssertTrue(files[0].isBinary)
        XCTAssertNil(files[0].added)
    }
}
