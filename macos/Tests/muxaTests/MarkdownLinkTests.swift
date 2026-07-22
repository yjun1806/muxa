import XCTest
@testable import muxa

final class MarkdownLinkTests: XCTestCase {
    // MARK: 외부 링크 — 시스템 브라우저로

    func testHTTPSIsExternal() {
        XCTAssertEqual(resolveMarkdownLink(href: "https://example.com/a", baseDir: "/docs"),
                       .external(URL(string: "https://example.com/a")!))
    }

    func testHTTPIsExternal() {
        XCTAssertEqual(resolveMarkdownLink(href: "http://a.com", baseDir: "/docs"),
                       .external(URL(string: "http://a.com")!))
    }

    func testMailtoIsExternal() {
        XCTAssertEqual(resolveMarkdownLink(href: "mailto:x@y.com", baseDir: "/docs"),
                       .external(URL(string: "mailto:x@y.com")!))
    }

    // MARK: 위험/미허용 스킴 — 무시(NSWorkspace로 넘기지 않는다)

    func testJavascriptSchemeIgnored() {
        XCTAssertEqual(resolveMarkdownLink(href: "javascript:alert(1)", baseDir: "/docs"), .ignore)
    }

    func testDataSchemeIgnored() {
        XCTAssertEqual(resolveMarkdownLink(href: "data:text/html,<h1>x</h1>", baseDir: "/docs"), .ignore)
    }

    func testCustomSchemeIgnored() {
        XCTAssertEqual(resolveMarkdownLink(href: "vscode://file/x", baseDir: "/docs"), .ignore)
    }

    func testUppercaseSchemeNormalized() {
        XCTAssertEqual(resolveMarkdownLink(href: "HTTPS://example.com", baseDir: "/docs"),
                       .external(URL(string: "HTTPS://example.com")!))
    }

    // MARK: 로컬 파일 — 앱 내 새 탭으로

    func testBareRelativeFile() {
        XCTAssertEqual(resolveMarkdownLink(href: "DESIGN.md", baseDir: "/docs"),
                       .localFile("/docs/DESIGN.md"))
    }

    func testDotSlashRelative() {
        XCTAssertEqual(resolveMarkdownLink(href: "./DESIGN.md", baseDir: "/docs"),
                       .localFile("/docs/DESIGN.md"))
    }

    func testParentRelative() {
        XCTAssertEqual(resolveMarkdownLink(href: "../README.md", baseDir: "/repo/docs"),
                       .localFile("/repo/README.md"))
    }

    func testNestedRelative() {
        XCTAssertEqual(resolveMarkdownLink(href: "sub/a.md", baseDir: "/docs"),
                       .localFile("/docs/sub/a.md"))
    }

    func testFragmentStrippedFromFile() {
        XCTAssertEqual(resolveMarkdownLink(href: "a.md#section", baseDir: "/docs"),
                       .localFile("/docs/a.md"))
    }

    func testPercentDecoded() {
        XCTAssertEqual(resolveMarkdownLink(href: "img%20name.png", baseDir: "/docs"),
                       .localFile("/docs/img name.png"))
    }

    func testFileScheme() {
        XCTAssertEqual(resolveMarkdownLink(href: "file:///abs/x.md", baseDir: "/docs"),
                       .localFile("/abs/x.md"))
    }

    func testAbsolutePathWithoutScheme() {
        XCTAssertEqual(resolveMarkdownLink(href: "/etc/hosts", baseDir: "/docs"),
                       .localFile("/etc/hosts"))
    }

    // MARK: 무시 — 앵커·빈 링크

    func testPureAnchorIgnored() {
        XCTAssertEqual(resolveMarkdownLink(href: "#section", baseDir: "/docs"), .ignore)
    }

    func testEmptyIgnored() {
        XCTAssertEqual(resolveMarkdownLink(href: "   ", baseDir: "/docs"), .ignore)
    }
}
