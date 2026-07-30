import Foundation
import Testing
@testable import muxa

/// 새 파일 판정. 틀리면 **삭제된 파일을 새 파일로 그리거나**(정반대의 사실),
/// 42줄짜리 초록 벽을 그대로 남긴다.
struct NewFileDiffTests {
    @Test func 새_파일은_new_file_mode를_싣는다() {
        let d = ["diff --git a/x.md b/x.md", "new file mode 100644", "index 000..abc",
                 "--- /dev/null", "+++ b/x.md", "@@ -0,0 +1,2 @@", "+# 제목", "+본문"]
        #expect(NewFileDiff.isNewFile(d))
    }

    /// 추적 안 되는 파일은 `--no-index`로 그리므로 `new file mode`가 없다.
    @Test func 미추적_파일은_dev_null_옛쪽으로_알아본다() {
        let d = ["diff --git a/tmp.md b/tmp.md", "--- /dev/null", "+++ b/tmp.md",
                 "@@ -0,0 +1 @@", "+메모"]
        #expect(NewFileDiff.isNewFile(d))
    }

    /// `+++ /dev/null`은 **새쪽**이 비었다는 뜻 = 삭제다. 접두만 보고 세면 정반대로 그린다.
    @Test func 삭제된_파일을_새_파일로_보지_않는다() {
        let d = ["diff --git a/gone.md b/gone.md", "deleted file mode 100644",
                 "--- a/gone.md", "+++ /dev/null", "@@ -1,2 +0,0 @@", "-# 제목", "-본문"]
        #expect(!NewFileDiff.isNewFile(d))
    }

    @Test func 보통_수정은_새_파일이_아니다() {
        let d = ["diff --git a/x.swift b/x.swift", "index abc..def 100644",
                 "--- a/x.swift", "+++ b/x.swift", "@@ -1,3 +1,3 @@", " 유지", "-옛", "+새"]
        #expect(!NewFileDiff.isNewFile(d))
    }

    @Test func 빈_diff는_새_파일이_아니다() {
        #expect(!NewFileDiff.isNewFile([]))
        #expect(!NewFileDiff.isNewFile([""]))
    }

    /// 본문에 `--- /dev/null`처럼 보이는 줄이 있어도 헤더를 지난 뒤면 무시한다.
    @Test func 본문에_들어서면_더_보지_않는다() {
        let d = ["diff --git a/x.md b/x.md", "index abc..def 100644",
                 "--- a/x.md", "+++ b/x.md", "@@ -1 +1,2 @@",
                 " 기존", "+새 file mode 100644", "+--- /dev/null"]
        #expect(!NewFileDiff.isNewFile(d))
    }

    // MARK: 줄 수

    @Test func 본문_추가줄만_센다() {
        let d = ["diff --git a/x.md b/x.md", "new file mode 100644",
                 "--- /dev/null", "+++ b/x.md", "@@ -0,0 +1,3 @@", "+a", "+b", "+c"]
        #expect(NewFileDiff.addedLineCount(d) == 3, "+++ 헤더는 세지 않는다")
    }

    @Test func 추가가_없으면_0이다() {
        #expect(NewFileDiff.addedLineCount(["--- a/x", "+++ b/x", "@@ -1 +0,0 @@", "-지움"]) == 0)
    }
}
