import Testing
@testable import muxa

/// 커밋 파일 목록 파싱 — 실제 `git show` 출력을 그대로 넣어 검증한다.
/// 픽스처는 이 리포에서 실측한 것이다(리네임 유사도·머지 결합 diff·바이너리 모두 실물).
struct GitCommitFileTests {

    // MARK: name-status

    @Test func testBasicStatuses() {
        let files = GitCommitFileParse.parseNameStatus("M\tREADME.md\nA\tnew.swift\nD\told.swift")
        #expect(files.map(\.status) == ["M", "A", "D"])
        #expect(files.map(\.path) == ["README.md", "new.swift", "old.swift"])
        #expect(files.allSatisfy { $0.oldPath == nil })
    }

    /// 리네임은 유사도 점수가 붙고 경로가 둘이다 — 새 경로가 path, 옛 경로가 oldPath.
    @Test func testRenameSplitsPaths() {
        let files = GitCommitFileParse.parseNameStatus("R060\tsrc/TopBar.tsx\tsrc/ContentHeader.tsx")
        #expect(files.count == 1)
        #expect(files[0].status == "R")
        #expect(files[0].path == "src/ContentHeader.tsx")
        #expect(files[0].oldPath == "src/TopBar.tsx")
    }

    @Test func testCopyBehavesLikeRename() {
        let files = GitCommitFileParse.parseNameStatus("C100\ta.swift\tb.swift")
        #expect(files[0].status == "C")
        #expect(files[0].path == "b.swift")
        #expect(files[0].oldPath == "a.swift")
    }

    /// 머지 커밋의 결합 diff는 부모 수만큼 상태 문자가 붙는다(`MM`) — 첫 글자만 쓴다.
    @Test func testMergeCombinedStatusTakesFirstChar() {
        let files = GitCommitFileParse.parseNameStatus("MM\tdocs/DESIGN.md")
        #expect(files[0].status == "M")
        #expect(files[0].path == "docs/DESIGN.md")
    }

    /// 머지 커밋(파일 내역 없음)·빈 커밋 → 빈 배열. 크래시도 지어낸 항목도 없다.
    @Test func testEmptyOutput() {
        #expect(GitCommitFileParse.parseNameStatus("").isEmpty)
        #expect(GitCommitFileParse.parseNameStatus("\n\n").isEmpty)
    }

    @Test func testTypeChange() {
        let files = GitCommitFileParse.parseNameStatus("T\tscripts/hook.sh")
        #expect(files[0].status == "T")
    }

    /// 한글 경로 — `core.quotepath=false` 전제(GitService.gitArgs가 항상 붙인다).
    @Test func testKoreanPath() {
        let files = GitCommitFileParse.parseNameStatus("M\tdocs/한글 문서.md")
        #expect(files[0].path == "docs/한글 문서.md")
    }

    @Test func testPathWithSpaces() {
        let files = GitCommitFileParse.parseNameStatus("A\tmy folder/some file.txt")
        #expect(files[0].path == "my folder/some file.txt")
    }

    // MARK: numstat

    @Test func testNumstatNumbers() {
        let stats = GitCommitFileParse.parseNumstat("133\t23\tREADME.md")
        #expect(stats["README.md"]?.added == 133)
        #expect(stats["README.md"]?.deleted == 23)
        #expect(stats["README.md"]?.binary == false)
    }

    /// 바이너리는 `-  -` — 0이 아니라 **모름**이다(0은 "안 바뀜"이라는 다른 사실).
    @Test func testNumstatBinaryIsUnknownNotZero() {
        let stats = GitCommitFileParse.parseNumstat("-\t-\tdocs/assets/real-git.png")
        let s = stats["docs/assets/real-git.png"]
        #expect(s?.binary == true)
        #expect(s?.added == nil)
        #expect(s?.deleted == nil)
    }

    @Test func testNumstatZeroIsNotNil() {
        let stats = GitCommitFileParse.parseNumstat("0\t0\tuntouched.txt")
        #expect(stats["untouched.txt"]?.added == 0)
        #expect(stats["untouched.txt"]?.deleted == 0)
    }

    // MARK: 리네임 경로 펴기

    @Test func testExpandBraceRename() {
        #expect(GitCommitFileParse.expandRenamePath("src/{TopBar.tsx => ContentHeader.tsx}") == "src/ContentHeader.tsx")
    }

    @Test func testExpandBraceInDirectory() {
        #expect(GitCommitFileParse.expandRenamePath("{old => new}/file.swift") == "new/file.swift")
    }

    @Test func testExpandBareRename() {
        #expect(GitCommitFileParse.expandRenamePath("a.txt => b.txt") == "b.txt")
    }

    @Test func testExpandLeavesPlainPath() {
        #expect(GitCommitFileParse.expandRenamePath("src/App.tsx") == "src/App.tsx")
    }

    /// 경로에 `{`가 있어도 화살표가 없으면 리네임이 아니다 — 건드리지 않는다.
    @Test func testExpandIgnoresBracesWithoutArrow() {
        #expect(GitCommitFileParse.expandRenamePath("src/{id}/page.tsx") == "src/{id}/page.tsx")
    }

    // MARK: 합치기

    @Test func testMergeJoinsStatsByPath() {
        let files = GitCommitFileParse.merge(
            nameStatus: "M\tREADME.md\nA\tdocs/new.md",
            numstat: "133\t23\tREADME.md\n10\t0\tdocs/new.md")
        #expect(files.count == 2)
        #expect(files[0].added == 133)
        #expect(files[0].deleted == 23)
        #expect(files[1].added == 10)
    }

    /// 리네임은 numstat이 경로를 압축해 내보낸다 — 펴서 이어야 짝이 맞는다.
    @Test func testMergeJoinsRenameAcrossCompressedPath() {
        let files = GitCommitFileParse.merge(
            nameStatus: "R060\tsrc/TopBar.tsx\tsrc/ContentHeader.tsx",
            numstat: "5\t6\tsrc/{TopBar.tsx => ContentHeader.tsx}")
        #expect(files.count == 1)
        #expect(files[0].path == "src/ContentHeader.tsx")
        #expect(files[0].oldPath == "src/TopBar.tsx")
        #expect(files[0].added == 5)
        #expect(files[0].deleted == 6)
    }

    /// **머지 커밋 비대칭** — name-status와 numstat의 줄 수가 다르다(실측 3 vs 15).
    /// 순서로 짝지으면 엉뚱한 숫자가 붙는다. 경로로 잇고, 짝이 없으면 침묵한다.
    @Test func testMergeAsymmetryDoesNotMisalign() {
        let files = GitCommitFileParse.merge(
            nameStatus: "MM\tdocs/DESIGN.md\nMM\tdocs/STATUS.md",
            numstat: "7\t0\tdocs/DESIGN.md\n27\t0\tdocs/STATUS.md\n35\t0\tsrc/Other.swift")
        #expect(files.count == 2, "기준 목록은 name-status다 — numstat 여분이 항목을 늘리지 않는다")
        #expect(files[0].path == "docs/DESIGN.md")
        #expect(files[0].added == 7)
        #expect(files[1].path == "docs/STATUS.md")
        #expect(files[1].added == 27)
    }

    /// 짝이 없으면 0을 지어내지 않는다.
    @Test func testMergeKeepsStatsNilWhenUnmatched() {
        let files = GitCommitFileParse.merge(nameStatus: "M\tghost.swift", numstat: "")
        #expect(files.count == 1)
        #expect(files[0].added == nil)
        #expect(files[0].deleted == nil)
        #expect(!(files[0].isBinary))
    }

    @Test func testMergeCarriesBinaryFlag() {
        let files = GitCommitFileParse.merge(
            nameStatus: "A\tdocs/assets/real-git.png",
            numstat: "-\t-\tdocs/assets/real-git.png")
        #expect(files[0].isBinary)
        #expect(files[0].added == nil)
    }
}
