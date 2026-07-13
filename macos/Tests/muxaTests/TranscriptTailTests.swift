import XCTest
@testable import muxa

/// transcript 꼬리 파싱 — "완료" 알림 본문을 Claude가 마지막으로 한 말로 채우는 경로.
final class TranscriptTailTests: XCTestCase {
    private func line(role: String, text: String) -> String {
        #"{"type":"\#(role)","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    func testFindsLastAssistantMessage() {
        let tail = [
            line(role: "assistant", text: "첫 응답"),
            line(role: "user", text: "그 다음은?"),
            line(role: "assistant", text: "마지막 응답"),
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "마지막 응답")
    }

    /// 사용자 메시지가 마지막이어도 그건 assistant 메시지가 아니다 — 거슬러 올라가야 한다.
    func testSkipsTrailingUserMessage() {
        let tail = [
            line(role: "assistant", text: "내 답"),
            line(role: "user", text: "다시 해줘"),
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "내 답")
    }

    /// 꼬리만 읽으므로 첫 줄은 청크 경계에서 잘려 있다 — 파싱 실패해도 무시하고 넘어가야 한다.
    func testIgnoresTruncatedFirstLine() {
        let tail = "sage\":{\"content\":[{\"type\":\"text\"...\n" + line(role: "assistant", text: "온전한 줄")
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "온전한 줄")
    }

    /// content 블록에 tool_use가 섞이면 text만 추린다(도구 호출 JSON이 알림 본문에 새면 안 된다).
    func testExtractsTextBlocksOnly() {
        let tail = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"},{"type":"text","text":"고쳤다"}]}}"#
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "고쳤다")
    }

    /// 도구 호출만 있는 턴은 보여줄 텍스트가 없다 — 더 거슬러 올라간다.
    func testSkipsToolOnlyAssistantTurn() {
        let tail = [
            line(role: "assistant", text: "실제 할 말"),
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "실제 할 말")
    }

    func testContentAsPlainString() {
        let tail = #"{"type":"assistant","message":{"content":"문자열 본문"}}"#
        XCTAssertEqual(TranscriptTail.lastAssistantMessage(inTail: tail), "문자열 본문")
    }

    func testEmptyAndGarbageTailsReturnNil() {
        XCTAssertNil(TranscriptTail.lastAssistantMessage(inTail: ""))
        XCTAssertNil(TranscriptTail.lastAssistantMessage(inTail: "쓰레기\n더 많은 쓰레기"))
        XCTAssertNil(TranscriptTail.lastAssistantMessage(inTail: line(role: "user", text: "나뿐이다")))
    }

    /// 실제 파일에서 읽는 경계 경로도 한 번은 태운다(꼬리 seek + 재시도 포함).
    func testReadsFromFile() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("muxa-transcript-\(UUID().uuidString).jsonl")
        let content = [line(role: "assistant", text: "옛 응답"), line(role: "assistant", text: "새 응답")]
            .joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let message = await TranscriptTail.lastAssistantMessage(atPath: url.path)
        XCTAssertEqual(message, "새 응답")
    }

    func testMissingFileReturnsNil() async {
        let message = await TranscriptTail.lastAssistantMessage(atPath: "/nonexistent/muxa/none.jsonl")
        XCTAssertNil(message)
    }
}
