import Foundation
import Testing
@testable import muxa

struct MarkdownLinkTests {
    // MARK: 외부 링크 — 시스템 브라우저로

    @Test func httpsIsExternal() {
        #expect(resolveMarkdownLink(href: "https://example.com/a", baseDir: "/docs") == .external(URL(string: "https://example.com/a")!))
    }

    @Test func httpIsExternal() {
        #expect(resolveMarkdownLink(href: "http://a.com", baseDir: "/docs") == .external(URL(string: "http://a.com")!))
    }

    @Test func mailtoIsExternal() {
        #expect(resolveMarkdownLink(href: "mailto:x@y.com", baseDir: "/docs") == .external(URL(string: "mailto:x@y.com")!))
    }

    // MARK: 위험/미허용 스킴 — 무시(NSWorkspace로 넘기지 않는다)

    @Test func javascriptSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "javascript:alert(1)", baseDir: "/docs") == .ignore)
    }

    @Test func dataSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "data:text/html,<h1>x</h1>", baseDir: "/docs") == .ignore)
    }

    @Test func customSchemeIgnored() {
        #expect(resolveMarkdownLink(href: "vscode://file/x", baseDir: "/docs") == .ignore)
    }

    @Test func uppercaseSchemeNormalized() {
        #expect(resolveMarkdownLink(href: "HTTPS://example.com", baseDir: "/docs") == .external(URL(string: "HTTPS://example.com")!))
    }

    // MARK: 로컬 파일 — 앱 내 새 탭으로

    @Test func bareRelativeFile() {
        #expect(resolveMarkdownLink(href: "DESIGN.md", baseDir: "/docs") == .localFile("/docs/DESIGN.md"))
    }

    @Test func dotSlashRelative() {
        #expect(resolveMarkdownLink(href: "./DESIGN.md", baseDir: "/docs") == .localFile("/docs/DESIGN.md"))
    }

    @Test func parentRelative() {
        #expect(resolveMarkdownLink(href: "../README.md", baseDir: "/repo/docs") == .localFile("/repo/README.md"))
    }

    @Test func nestedRelative() {
        #expect(resolveMarkdownLink(href: "sub/a.md", baseDir: "/docs") == .localFile("/docs/sub/a.md"))
    }

    @Test func fragmentStrippedFromFile() {
        #expect(resolveMarkdownLink(href: "a.md#section", baseDir: "/docs") == .localFile("/docs/a.md"))
    }

    @Test func percentDecoded() {
        #expect(resolveMarkdownLink(href: "img%20name.png", baseDir: "/docs") == .localFile("/docs/img name.png"))
    }

    @Test func fileScheme() {
        #expect(resolveMarkdownLink(href: "file:///abs/x.md", baseDir: "/docs") == .localFile("/abs/x.md"))
    }

    @Test func absolutePathWithoutScheme() {
        #expect(resolveMarkdownLink(href: "/etc/hosts", baseDir: "/docs") == .localFile("/etc/hosts"))
    }

    // MARK: 무시 — 앵커·빈 링크

    @Test func pureAnchorIgnored() {
        #expect(resolveMarkdownLink(href: "#section", baseDir: "/docs") == .ignore)
    }

    @Test func emptyIgnored() {
        #expect(resolveMarkdownLink(href: "   ", baseDir: "/docs") == .ignore)
    }
}
