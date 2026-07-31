import Foundation
import Testing
@testable import muxa

struct MarkdownLinkTests {
    // MARK: 외부 링크 — 시스템 브라우저로

    @Test func testHTTPSIsExternal() {
        #expect(resolveMarkdownLink(href: "https://example.com/a", baseDir: "/docs") == .external(URL(string: "https://example.com/a")!))
    }

    @Test func testHTTPIsExternal() {
        #expect(resolveMarkdownLink(href: "http://a.com", baseDir: "/docs") == .external(URL(string: "http://a.com")!))
    }

    @Test func testMailtoIsExternal() {
        #expect(resolveMarkdownLink(href: "mailto:x@y.com", baseDir: "/docs") == .external(URL(string: "mailto:x@y.com")!))
    }

    // MARK: 위험/미허용 스킴 — 무시(NSWorkspace로 넘기지 않는다)

    @Test func testJavascriptSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "javascript:alert(1)", baseDir: "/docs") == .ignore)
    }

    @Test func testDataSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "data:text/html,<h1>x</h1>", baseDir: "/docs") == .ignore)
    }

    @Test func testCustomSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "vscode://file/x", baseDir: "/docs") == .ignore)
    }

    @Test func testUppercaseSchemeNormalized() {
        #expect(resolveMarkdownLink(href: "HTTPS://example.com", baseDir: "/docs") == .external(URL(string: "HTTPS://example.com")!))
    }

    // MARK: 로컬 파일 — 앱 내 새 탭으로

    @Test func testBareRelativeFile() {
        #expect(resolveMarkdownLink(href: "DESIGN.md", baseDir: "/docs") == .localFile("/docs/DESIGN.md"))
    }

    @Test func testDotSlashRelative() {
        #expect(resolveMarkdownLink(href: "./DESIGN.md", baseDir: "/docs") == .localFile("/docs/DESIGN.md"))
    }

    @Test func testParentRelative() {
        #expect(resolveMarkdownLink(href: "../README.md", baseDir: "/repo/docs") == .localFile("/repo/README.md"))
    }

    @Test func testNestedRelative() {
        #expect(resolveMarkdownLink(href: "sub/a.md", baseDir: "/docs") == .localFile("/docs/sub/a.md"))
    }

    @Test func testFragmentStrippedFromFile() {
        #expect(resolveMarkdownLink(href: "a.md#section", baseDir: "/docs") == .localFile("/docs/a.md"))
    }

    @Test func testPercentDecoded() {
        #expect(resolveMarkdownLink(href: "img%20name.png", baseDir: "/docs") == .localFile("/docs/img name.png"))
    }

    @Test func testFileScheme() {
        #expect(resolveMarkdownLink(href: "file:///abs/x.md", baseDir: "/docs") == .localFile("/abs/x.md"))
    }

    @Test func testAbsolutePathWithoutScheme() {
        #expect(resolveMarkdownLink(href: "/etc/hosts", baseDir: "/docs") == .localFile("/etc/hosts"))
    }

    // MARK: 무시 — 앵커·빈 링크

    @Test func testPureAnchorIgnored() {
        #expect(resolveMarkdownLink(href: "#section", baseDir: "/docs") == .ignore)
    }

    @Test func testEmptyIgnored() {
        #expect(resolveMarkdownLink(href: "   ", baseDir: "/docs") == .ignore)
    }
}
