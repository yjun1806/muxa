import XCTest

@testable import muxa

/// transcript 꼬리에서 **마지막 진짜 user 프롬프트**를 뽑는 경로 —
/// 백그라운드 팝오버(❯ 내 지시)와 사이드바 hover 팝오버(이미지 포함)가 공용으로 쓴다.
/// 핵심은 오염 차단이다: tool_result·meta·사이드체인·슬래시 명령 배관은 user 줄이어도 프롬프트가 아니다.
final class TranscriptUserTailTests: XCTestCase {
    private func line(role: String, text: String) -> String {
        #"{"type":"\#(role)","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    // MARK: 텍스트

    func testFindsLastUserPrompt() {
        let tail = [
            line(role: "user", text: "첫 지시"),
            line(role: "assistant", text: "답했다"),
            line(role: "user", text: "마지막 지시"),
            line(role: "assistant", text: "또 답했다"),
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastUserMessage(inTail: tail)?.text, "마지막 지시")
    }

    /// 도구 결과는 user 줄로 들어오지만 사람의 지시가 아니다 — 건너뛴다.
    func testSkipsToolResultUserLines() {
        let tail = [
            line(role: "user", text: "진짜 지시"),
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"파일 내용"}]}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastUserMessage(inTail: tail)?.text, "진짜 지시")
    }

    /// meta 줄(시스템 삽입)·사이드체인(서브에이전트 대화)은 내 프롬프트가 아니다.
    func testSkipsMetaAndSidechainLines() {
        let tail = [
            line(role: "user", text: "내 지시"),
            #"{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Caveat: 시스템 안내"}]}}"#,
            #"{"type":"user","isSidechain":true,"message":{"content":[{"type":"text","text":"서브에이전트 프롬프트"}]}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastUserMessage(inTail: tail)?.text, "내 지시")
    }

    /// 슬래시 명령 배관(`<command-name>…`)은 지시가 아니라 로그다.
    func testSkipsSlashCommandPlumbing() {
        let tail = [
            line(role: "user", text: "리뷰 돌려줘"),
            #"{"type":"user","message":{"content":[{"type":"text","text":"<command-name>/clear</command-name>"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"text","text":"<local-command-stdout>done</local-command-stdout>"}]}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(TranscriptTail.lastUserMessage(inTail: tail)?.text, "리뷰 돌려줘")
    }

    func testContentAsPlainString() {
        let tail = #"{"type":"user","message":{"content":"문자열 지시"}}"#
        XCTAssertEqual(TranscriptTail.lastUserMessage(inTail: tail)?.text, "문자열 지시")
    }

    func testEmptyAndGarbageReturnNil() {
        XCTAssertNil(TranscriptTail.lastUserMessage(inTail: ""))
        XCTAssertNil(TranscriptTail.lastUserMessage(inTail: "쓰레기"))
        XCTAssertNil(TranscriptTail.lastUserMessage(inTail: line(role: "assistant", text: "나뿐")))
    }

    // MARK: 이미지

    /// 1×1 PNG의 base64 — 진짜 디코딩이 되는 최소 데이터.
    private let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private var imageLine: String {
        #"{"type":"user","message":{"content":[{"type":"text","text":"이 스크린샷 봐줘"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"\#(pngBase64)"}}]}}"#
    }

    func testCountsImagesInLastUserMessage() {
        let message = TranscriptTail.lastUserMessage(inTail: imageLine)
        XCTAssertEqual(message?.text, "이 스크린샷 봐줘")
        XCTAssertEqual(message?.imageCount, 1)
    }

    /// 이미지만 있는 프롬프트도 유효하다(팝오버가 이미지를 보여주면 된다).
    func testImageOnlyUserMessageSurvives() {
        let tail = #"{"type":"user","message":{"content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"\#(pngBase64)"}}]}}"#
        let message = TranscriptTail.lastUserMessage(inTail: tail)
        XCTAssertEqual(message?.text, "")
        XCTAssertEqual(message?.imageCount, 1)
    }

    func testExtractsImageDataFromLastUserMessage() {
        let images = TranscriptTail.lastUserImages(inTail: imageLine, limit: 3)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first, Data(base64Encoded: pngBase64))
    }

    /// 이미지는 마지막 user 메시지의 것만 — 이전 턴의 이미지가 새면 "그 스크린샷"이 뒤바뀐다.
    func testImagesComeFromLastUserMessageOnly() {
        let tail = [imageLine, line(role: "user", text: "이미지 없는 새 지시")].joined(separator: "\n")
        XCTAssertTrue(TranscriptTail.lastUserImages(inTail: tail, limit: 3).isEmpty)
    }

    func testImageLimitIsRespected() {
        let block = #"{"type":"image","source":{"type":"base64","media_type":"image/png","data":"\#(pngBase64)"}}"#
        let tail = #"{"type":"user","message":{"content":[\#(block),\#(block),\#(block)]}}"#
        XCTAssertEqual(TranscriptTail.lastUserImages(inTail: tail, limit: 2).count, 2)
    }

    // MARK: 파일 경계

    func testReadsFromFile() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("muxa-usertail-\(UUID().uuidString).jsonl")
        let content = [line(role: "user", text: "옛 지시"), line(role: "user", text: "새 지시")]
            .joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let message = await TranscriptTail.lastUserMessage(atPath: url.path)
        XCTAssertEqual(message?.text, "새 지시")
    }

    func testMissingFileReturnsNil() async {
        let message = await TranscriptTail.lastUserMessage(atPath: "/nonexistent/muxa/none.jsonl")
        XCTAssertNil(message)
    }
}
