import XCTest
@testable import muxa

/// 경로 자동완성 분해 — 터미널 cd 스타일. 분해(순수)만 테스트(디렉토리 읽기는 파일시스템 의존).
final class PathCompleteTests: XCTestCase {
    private let base = "/Users/yj/project"

    /// 빈 입력 → base 전체.
    func testEmptyIsBase() {
        let (dir, prefix) = PathComplete.split("", base: base)
        XCTAssertEqual(dir, base)
        XCTAssertEqual(prefix, "")
    }

    /// 접두사 — 마지막 조각이 필터.
    func testPrefixSplit() {
        let (dir, prefix) = PathComplete.split("src", base: base)
        XCTAssertEqual(dir, base)
        XCTAssertEqual(prefix, "src")
    }

    /// 끝이 / → 그 디렉토리 전체.
    func testTrailingSlashIsDir() {
        let (dir, prefix) = PathComplete.split("apps/", base: base)
        XCTAssertEqual(dir, base + "/apps")
        XCTAssertEqual(prefix, "")
    }

    /// 하위 경로 접두사.
    func testNestedPrefix() {
        let (dir, prefix) = PathComplete.split("apps/we", base: base)
        XCTAssertEqual(dir, base + "/apps")
        XCTAssertEqual(prefix, "we")
    }

    /// 절대경로 — 루트에서.
    func testAbsolute() {
        let (dir, prefix) = PathComplete.split("/usr/lo", base: base)
        XCTAssertEqual(dir, "/usr")
        XCTAssertEqual(prefix, "lo")
    }

    /// 상위(..) 정규화.
    func testParentTraversal() {
        let (dir, prefix) = PathComplete.split("../", base: base)
        XCTAssertEqual(dir, "/Users/yj")
        XCTAssertEqual(prefix, "")
    }

    /// 홈(~) 확장.
    func testTildeExpand() {
        let (dir, _) = PathComplete.split("~/Doc", base: base)
        XCTAssertEqual(dir, NSHomeDirectory())
    }

    /// 표시 축약 — 홈은 ~.
    func testDisplayShortensHome() {
        XCTAssertEqual(PathComplete.display(NSHomeDirectory() + "/code"), "~/code")
        XCTAssertEqual(PathComplete.display("/tmp/x"), "/tmp/x")
    }
}
