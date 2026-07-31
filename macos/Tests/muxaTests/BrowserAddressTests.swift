import Foundation
import Testing
@testable import muxa

struct BrowserAddressTests {
    @Test func httpsPassthrough() {
        #expect(normalizeBrowserAddress("https://a.com") == URL(string: "https://a.com"))
    }

    @Test func httpPassthrough() {
        #expect(normalizeBrowserAddress("http://a.com") == URL(string: "http://a.com"))
    }

    @Test func bareHostGetsHTTPS() {
        #expect(normalizeBrowserAddress("example.com") == URL(string: "https://example.com"))
    }

    @Test func hostWithPathAndQuery() {
        #expect(normalizeBrowserAddress("example.com/x?q=1") == URL(string: "https://example.com/x?q=1"))
    }

    @Test func localhostWithPort() {
        #expect(normalizeBrowserAddress("localhost:3000") == URL(string: "https://localhost:3000"))
    }

    @Test func whitespaceTrimmed() {
        #expect(normalizeBrowserAddress("  https://a.com  ") == URL(string: "https://a.com"))
    }

    @Test func emptyIsNil() {
        #expect(normalizeBrowserAddress("   ") == nil)
    }

    @Test func searchPhraseIsNil() {
        #expect(normalizeBrowserAddress("hello world foo") == nil)
    }

    @Test func uppercaseSchemeAccepted() {
        #expect(normalizeBrowserAddress("HTTPS://A.com") == URL(string: "HTTPS://A.com"))
    }
}
