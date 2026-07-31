import Foundation
import Testing
@testable import muxa

/// 경로 자동완성 분해 — 터미널 cd 스타일. 분해(순수)만 테스트(디렉토리 읽기는 파일시스템 의존).
struct PathCompleteTests {
    private let base = "/Users/yj/project"

    /// 빈 입력 → base 전체.
    @Test func testEmptyIsBase() {
        let (dir, prefix) = PathComplete.split("", base: base)
        #expect(dir == base)
        #expect(prefix == "")
    }

    /// 접두사 — 마지막 조각이 필터.
    @Test func testPrefixSplit() {
        let (dir, prefix) = PathComplete.split("src", base: base)
        #expect(dir == base)
        #expect(prefix == "src")
    }

    /// 끝이 / → 그 디렉토리 전체.
    @Test func testTrailingSlashIsDir() {
        let (dir, prefix) = PathComplete.split("apps/", base: base)
        #expect(dir == base + "/apps")
        #expect(prefix == "")
    }

    /// 하위 경로 접두사.
    @Test func testNestedPrefix() {
        let (dir, prefix) = PathComplete.split("apps/we", base: base)
        #expect(dir == base + "/apps")
        #expect(prefix == "we")
    }

    /// 절대경로 — 루트에서.
    @Test func testAbsolute() {
        let (dir, prefix) = PathComplete.split("/usr/lo", base: base)
        #expect(dir == "/usr")
        #expect(prefix == "lo")
    }

    /// 상위(..) 정규화.
    @Test func testParentTraversal() {
        let (dir, prefix) = PathComplete.split("../", base: base)
        #expect(dir == "/Users/yj")
        #expect(prefix == "")
    }

    /// 홈(~) 확장.
    @Test func testTildeExpand() {
        let (dir, _) = PathComplete.split("~/Doc", base: base)
        #expect(dir == NSHomeDirectory())
    }

    /// 표시 축약 — 홈은 ~.
    @Test func testDisplayShortensHome() {
        #expect(PathComplete.display(NSHomeDirectory() + "/code") == "~/code")
        #expect(PathComplete.display("/tmp/x") == "/tmp/x")
    }
}
