import XCTest
@testable import muxa

/// IDE 통합 프로토콜의 순수 코어 — ws 핸드셰이크·프레임·JSON-RPC·MCP 응답·락파일. 소켓 없이 못 박는다.
final class IdeProtocolTests: XCTestCase {

    // MARK: 핸드셰이크

    func testAcceptKeyMatchesRfc6455Vector() {
        // RFC 6455 §1.3 표준 예시.
        XCTAssertEqual(IdeWsHandshake.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ=="),
                       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    private func upgrade(auth: String? = "abcdefghij0123456789") -> IdeWsHandshake.Request {
        var raw = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        if let auth { raw += "x-claude-code-ide-authorization: \(auth)\r\n" }
        raw += "\r\n"
        return IdeWsHandshake.parse(raw)!
    }

    func testValidUpgradePasses() {
        let token = "abcdefghij0123456789"
        XCTAssertNil(IdeWsHandshake.rejectReason(upgrade(auth: token), expectedToken: token))
    }

    func testMissingAuthHeaderRejected() {
        XCTAssertNotNil(IdeWsHandshake.rejectReason(upgrade(auth: nil), expectedToken: "abcdefghij0123456789"))
    }

    func testWrongTokenRejected() {
        XCTAssertNotNil(IdeWsHandshake.rejectReason(upgrade(auth: "wrongwrongwrong0000"),
                                                    expectedToken: "abcdefghij0123456789"))
    }

    func testNilExpectedTokenSkipsAuth() {
        XCTAssertNil(IdeWsHandshake.rejectReason(upgrade(auth: nil), expectedToken: nil))
    }

    func testConstantTimeEqual() {
        XCTAssertTrue(IdeWsHandshake.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(IdeWsHandshake.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(IdeWsHandshake.constantTimeEqual("abc", "abcd"))
    }

    // MARK: 프레임 코덱

    func testTextFrameRoundTrips() {
        let data = IdeWsFrame.encodeText("hello")
        guard case let .frame(f, consumed) = IdeWsFrame.decode(data) else { return XCTFail() }
        XCTAssertEqual(f.opcode, IdeWsFrame.Opcode.text.rawValue)
        XCTAssertTrue(f.fin)
        XCTAssertEqual(String(decoding: f.payload, as: UTF8.self), "hello")
        XCTAssertEqual(consumed, data.count)
    }

    func testMaskedClientFrameIsUnmasked() {
        // 클라→서버 마스크 프레임을 손으로 만든다: "hi" ^ mask.
        let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
        let text: [UInt8] = Array("hi".utf8)
        var frame: [UInt8] = [0x81, 0x82] // FIN+text, masked+len2
        frame += mask
        frame += text.enumerated().map { $0.element ^ mask[$0.offset % 4] }
        guard case let .frame(f, _) = IdeWsFrame.decode(Data(frame)) else { return XCTFail() }
        XCTAssertEqual(String(decoding: f.payload, as: UTF8.self), "hi")
    }

    func testIncompleteFrameReported() {
        if case .incomplete = IdeWsFrame.decode(Data([0x81])) {} else { XCTFail() }
    }

    func testExtendedLength126RoundTrips() {
        let big = String(repeating: "x", count: 300)
        let data = IdeWsFrame.encodeText(big)
        guard case let .frame(f, _) = IdeWsFrame.decode(data) else { return XCTFail() }
        XCTAssertEqual(f.payload.count, 300)
    }

    // MARK: JSON-RPC

    func testParseRequestKeepsIntId() {
        let r = IdeJsonRpc.parse(#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#)
        XCTAssertEqual(r?.method, "tools/list")
        XCTAssertEqual(r?.id as? Int, 7)
        XCTAssertFalse(r!.isNotification)
    }

    func testParseNotificationHasNoId() {
        let r = IdeJsonRpc.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertTrue(r!.isNotification)
    }

    func testParseRejectsWrongJsonrpc() {
        XCTAssertNil(IdeJsonRpc.parse(#"{"jsonrpc":"1.0","method":"x"}"#))
    }

    func testResponseEchoesIntIdNotFloat() {
        let data = IdeJsonRpc.responseData(id: 7, result: ["ok": true])!
        let s = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(s.contains("\"id\":7"), s) // 7.0 아님
    }

    // MARK: MCP 응답

    func testInitializeResultLoggingIsEmptyObject() {
        let data = try! JSONSerialization.data(withJSONObject: IdeProtocol.initializeResult(version: "0.3.0"))
        let s = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(s.contains("\"logging\":{}"), s) // [] 아니고 {}
        XCTAssertTrue(s.contains("\"protocolVersion\":\"2024-11-05\""), s)
    }

    func testToolsListHasTenTools() {
        let tools = IdeProtocol.toolsListResult["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 10)
        let names = Set(tools!.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("getCurrentSelection"))
        XCTAssertTrue(names.contains("openDiff"))
    }

    func testSelectionTextNilIsFailure() {
        XCTAssertTrue(IdeProtocol.selectionText(nil).contains("\"success\":false"))
    }

    func testSelectionTextEncodesRange() {
        let sel = IdeSelection(filePath: "/a/b.swift", text: "hi",
                               startLine: 2, startCharacter: 0, endLine: 2, endCharacter: 2)
        let text = IdeProtocol.selectionText(sel)
        XCTAssertTrue(text.contains("\"success\":true"))
        XCTAssertTrue(text.contains("\"filePath\":\"\\/a\\/b.swift\"") || text.contains("\"filePath\":\"/a/b.swift\""))
        XCTAssertTrue(text.contains("\"isEmpty\":false"))
    }

    // MARK: 락파일

    func testLockfileContentFields() {
        let c = IdeLockfile.content(pid: 4321, workspaceFolders: ["/p"], ideName: "muxa", authToken: "tok")
        XCTAssertEqual(c["transport"] as? String, "ws")
        XCTAssertEqual(c["pid"] as? Int, 4321)
        XCTAssertEqual(c["workspaceFolders"] as? [String], ["/p"])
    }

    func testAuthTokenIs32LowercaseHex() {
        let t = IdeLockfile.newAuthToken()
        XCTAssertEqual(t.count, 32)
        XCTAssertTrue(t.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testDefaultIsAliveTrueForSelf() {
        XCTAssertTrue(IdeLockfile.defaultIsAlive(ProcessInfo.processInfo.processIdentifier))
    }
}
