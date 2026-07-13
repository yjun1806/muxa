import XCTest
@testable import muxa

/// 도구 → 사람이 읽는 한 줄. LLM 없이 즉시 만든다.
final class ToolActivityTests: XCTestCase {
    func testFilePathsShowFilenameOnly() {
        XCTAssertEqual(
            ToolActivity.describe(toolName: "Edit", input: ["file_path": "/long/path/to/TermView.swift"]),
            "편집 중: TermView.swift"
        )
        XCTAssertEqual(
            ToolActivity.describe(toolName: "Read", input: ["file_path": "/a/README.md"]),
            "읽는 중: README.md"
        )
    }

    /// 명령줄 전체는 길고 시끄럽다 — 첫 토큰만.
    func testBashShowsFirstTokenOnly() {
        XCTAssertEqual(
            ToolActivity.describe(toolName: "Bash", input: ["command": "swift build --verbose 2>&1 | tail"]),
            "실행 중: swift"
        )
    }

    func testWebFetchShowsHostOnly() {
        XCTAssertEqual(
            ToolActivity.describe(toolName: "WebFetch", input: ["url": "https://docs.example.com/a/b?x=1"]),
            "웹 읽는 중: docs.example.com"
        )
    }

    func testLongPatternIsTruncated() {
        let long = String(repeating: "x", count: 60)
        let result = ToolActivity.describe(toolName: "Grep", input: ["pattern": long])
        XCTAssertEqual(result, "검색 중: \(String(repeating: "x", count: 30))…")
    }

    /// 인자가 없어도 라벨은 보여준다 — 무음보다 낫다.
    func testMissingArgumentStillShowsLabel() {
        XCTAssertEqual(ToolActivity.describe(toolName: "Edit", input: [:]), "편집 중")
    }

    /// 모르는 도구는 이름 그대로 — 스키마가 늘어도 표시가 죽지 않는다.
    func testUnknownToolFallsBackToName() {
        XCTAssertEqual(ToolActivity.describe(toolName: "SomeNewTool", input: [:]), "SomeNewTool")
    }

    func testNoToolNameIsNil() {
        XCTAssertNil(ToolActivity.describe(toolName: nil, input: ["file_path": "/a.swift"]))
        XCTAssertNil(ToolActivity.describe(toolName: "", input: [:]))
    }

    /// 도구 입력에 중첩 객체가 와도 문자열 필드만 걸러 쓴다(크래시 없이).
    func testNestedToolInputIsIgnoredGracefully() {
        let payload = ClaudeHookPayload.parse(Data(#"{"tool_name":"Edit","tool_input":{"file_path":"/a/B.swift","edits":[{"x":1}]}}"#.utf8))
        XCTAssertEqual(payload?.toolInput, ["file_path": "/a/B.swift"])
        XCTAssertEqual(ToolActivity.describe(toolName: payload?.toolName, input: payload?.toolInput ?? [:]), "편집 중: B.swift")
    }
}
