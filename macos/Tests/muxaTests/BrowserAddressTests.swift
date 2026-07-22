import XCTest
@testable import muxa

final class BrowserAddressTests: XCTestCase {
    func testHTTPSPassthrough() {
        XCTAssertEqual(normalizeBrowserAddress("https://a.com"), URL(string: "https://a.com"))
    }

    func testHTTPPassthrough() {
        XCTAssertEqual(normalizeBrowserAddress("http://a.com"), URL(string: "http://a.com"))
    }

    func testBareHostGetsHTTPS() {
        XCTAssertEqual(normalizeBrowserAddress("example.com"), URL(string: "https://example.com"))
    }

    func testHostWithPathAndQuery() {
        XCTAssertEqual(normalizeBrowserAddress("example.com/x?q=1"),
                       URL(string: "https://example.com/x?q=1"))
    }

    func testLocalhostWithPort() {
        XCTAssertEqual(normalizeBrowserAddress("localhost:3000"),
                       URL(string: "https://localhost:3000"))
    }

    func testWhitespaceTrimmed() {
        XCTAssertEqual(normalizeBrowserAddress("  https://a.com  "), URL(string: "https://a.com"))
    }

    func testEmptyIsNil() {
        XCTAssertNil(normalizeBrowserAddress("   "))
    }

    func testSearchPhraseIsNil() {
        XCTAssertNil(normalizeBrowserAddress("hello world foo"))
    }

    func testUppercaseSchemeAccepted() {
        XCTAssertEqual(normalizeBrowserAddress("HTTPS://A.com"), URL(string: "HTTPS://A.com"))
    }
}
