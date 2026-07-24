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

    func testSubprotocolEchoedWhenMcpOffered() {
        // claude(2.1.218)는 mcp 서브프로토콜을 요구 — echo 없으면 업그레이드 직후 끊는다.
        XCTAssertEqual(IdeWsHandshake.negotiateSubprotocol("mcp"), "mcp")
        XCTAssertEqual(IdeWsHandshake.negotiateSubprotocol("foo, mcp"), "mcp")
        XCTAssertNil(IdeWsHandshake.negotiateSubprotocol("foo"))
        XCTAssertNil(IdeWsHandshake.negotiateSubprotocol(nil))
        let resp = IdeWsHandshake.successResponse(secWebSocketKey: "dGhlIHNhbXBsZSBub25jZQ==", subprotocol: "mcp")
        XCTAssertTrue(resp.contains("Sec-WebSocket-Protocol: mcp\r\n"), resp)
        // 서브프로토콜 없으면 그 헤더 없음.
        XCTAssertFalse(IdeWsHandshake.successResponse(secWebSocketKey: "x").contains("Sec-WebSocket-Protocol"))
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

    func testHugeDeclaredLengthIsError() {
        // FIN+text, masked, len=127(64-bit) + 거대 길이 → 버퍼 무한증식 방어로 .error.
        var f: [UInt8] = [0x81, 0xFF]
        f += [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] // 2^64-1
        if case .error = IdeWsFrame.decode(Data(f)) {} else { XCTFail() }
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

    func testToolsListAdvertisesOnlySupportedTools() {
        let tools = IdeProtocol.toolsListResult["tools"] as? [[String: Any]]
        let names = Set(tools!.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, IdeProtocol.supportedTools)
        XCTAssertTrue(names.contains("getCurrentSelection"))
        // 쓰기 계열은 아직 광고 안 함(편집 반려 방지).
        XCTAssertFalse(names.contains("openDiff"))
        XCTAssertFalse(names.contains("saveDocument"))
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

    // MARK: 문서 선택 브리지

    func testDocSelectionParsesMessage() {
        let body: [String: Any] = ["text": "hi", "startLine": 2, "startChar": 1, "endLine": 3, "endChar": 4]
        let sel = DocSelectionBridge.selection(from: body, filePath: "/a/b.swift")
        XCTAssertEqual(sel?.text, "hi")
        XCTAssertEqual(sel?.startLine, 2)
        XCTAssertEqual(sel?.endCharacter, 4)
        XCTAssertEqual(sel?.filePath, "/a/b.swift")
        XCTAssertFalse(sel!.isEmpty)
    }

    func testDocSelectionEmptyTextIsEmptySelection() {
        let sel = DocSelectionBridge.selection(from: ["text": ""], filePath: "/a")
        XCTAssertTrue(sel!.isEmpty)
    }

    func testDocSelectionNonDictReturnsNil() {
        XCTAssertNil(DocSelectionBridge.selection(from: "nope", filePath: "/a"))
    }
}
