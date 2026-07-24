import XCTest
@testable import muxa

/// `@`멘션 경로 선택 — CC cwd 아래면 상대, 밖/미상이면 절대. 순수 판정이라 뷰 없이 못 박는다.
final class AtMentionTests: XCTestCase {

    func testRelativeWhenUnderBase() {
        XCTAssertEqual(AtMention.path(for: "/Users/x/proj/src/App.swift", relativeTo: "/Users/x/proj"),
                       "src/App.swift")
    }

    func testTrailingSlashOnBaseIsHandled() {
        XCTAssertEqual(AtMention.path(for: "/Users/x/proj/a.md", relativeTo: "/Users/x/proj/"),
                       "a.md")
    }

    func testAbsoluteWhenOutsideBase() {
        // 프로젝트 밖 파일 — 상대화하면 CC가 못 연다. 절대경로 그대로 둔다.
        XCTAssertEqual(AtMention.path(for: "/etc/hosts", relativeTo: "/Users/x/proj"),
                       "/etc/hosts")
    }

    func testPrefixBoundaryIsExact() {
        // "/Users/x/proj-other"는 "/Users/x/proj"의 접두지만 경계가 아니다 — 상대화하면 안 된다.
        XCTAssertEqual(AtMention.path(for: "/Users/x/proj-other/a.swift", relativeTo: "/Users/x/proj"),
                       "/Users/x/proj-other/a.swift")
    }

    func testNilOrEmptyOrRootBaseFallsBackToAbsolute() {
        XCTAssertEqual(AtMention.path(for: "/a/b.swift", relativeTo: nil), "/a/b.swift")
        XCTAssertEqual(AtMention.path(for: "/a/b.swift", relativeTo: ""), "/a/b.swift")
        XCTAssertEqual(AtMention.path(for: "/a/b.swift", relativeTo: "/"), "/a/b.swift")
    }

    func testFileEqualToBaseReturnsOriginal() {
        // 경로가 base 자신이면(디렉터리) 상대분이 비어 원본을 돌려준다.
        XCTAssertEqual(AtMention.path(for: "/Users/x/proj", relativeTo: "/Users/x/proj"),
                       "/Users/x/proj")
    }
}
