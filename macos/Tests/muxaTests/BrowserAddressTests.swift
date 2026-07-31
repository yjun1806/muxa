import Foundation
import Testing
@testable import muxa

struct BrowserAddressTests {
    @Test func testHTTPSPassthrough() {
        #expect(normalizeBrowserAddress("https://a.com") == URL(string: "https://a.com"))
    }

    @Test func testHTTPPassthrough() {
        #expect(normalizeBrowserAddress("http://a.com") == URL(string: "http://a.com"))
    }

    @Test func testBareHostGetsHTTPS() {
        #expect(normalizeBrowserAddress("example.com") == URL(string: "https://example.com"))
    }

    @Test func testHostWithPathAndQuery() {
        #expect(normalizeBrowserAddress("example.com/x?q=1") == URL(string: "https://example.com/x?q=1"))
    }

    @Test func testLocalhostWithPort() {
        #expect(normalizeBrowserAddress("localhost:3000") == URL(string: "https://localhost:3000"))
    }

    @Test func testWhitespaceTrimmed() {
        #expect(normalizeBrowserAddress("  https://a.com  ") == URL(string: "https://a.com"))
    }

    @Test func testEmptyIsNil() {
        #expect(normalizeBrowserAddress("   ") == nil)
    }

    @Test func testSearchPhraseIsNil() {
        #expect(normalizeBrowserAddress("hello world foo") == nil)
    }

    @Test func testUppercaseSchemeAccepted() {
        #expect(normalizeBrowserAddress("HTTPS://A.com") == URL(string: "HTTPS://A.com"))
    }
}
