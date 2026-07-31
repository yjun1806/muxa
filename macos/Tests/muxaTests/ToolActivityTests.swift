import Foundation
import Testing
@testable import muxa

/// 도구 → 사람이 읽는 한 줄. LLM 없이 즉시 만든다.
struct ToolActivityTests {
    @Test func filePathsShowFilenameOnly() {
        #expect(ToolActivity.describe(toolName: "Edit", input: ["file_path": "/long/path/to/TermView.swift"]) == "편집 중: TermView.swift")
        #expect(ToolActivity.describe(toolName: "Read", input: ["file_path": "/a/README.md"]) == "읽는 중: README.md")
    }

    /// 명령줄 전체는 길고 시끄럽다 — 첫 토큰만.
    @Test func bashShowsFirstTokenOnly() {
        #expect(ToolActivity.describe(toolName: "Bash", input: ["command": "swift build --verbose 2>&1 | tail"]) == "실행 중: swift")
    }

    @Test func webFetchShowsHostOnly() {
        #expect(ToolActivity.describe(toolName: "WebFetch", input: ["url": "https://docs.example.com/a/b?x=1"]) == "웹 읽는 중: docs.example.com")
    }

    @Test func longPatternIsTruncated() {
        let long = String(repeating: "x", count: 60)
        let result = ToolActivity.describe(toolName: "Grep", input: ["pattern": long])
        #expect(result == "검색 중: \(String(repeating: "x", count: 30))…")
    }

    /// 인자가 없어도 라벨은 보여준다 — 무음보다 낫다.
    @Test func missingArgumentStillShowsLabel() {
        #expect(ToolActivity.describe(toolName: "Edit", input: [:]) == "편집 중")
    }

    /// 모르는 도구는 이름 그대로 — 스키마가 늘어도 표시가 죽지 않는다.
    @Test func unknownToolFallsBackToName() {
        #expect(ToolActivity.describe(toolName: "SomeNewTool", input: [:]) == "SomeNewTool")
    }

    @Test func noToolNameIsNil() {
        #expect(ToolActivity.describe(toolName: nil, input: ["file_path": "/a.swift"]) == nil)
        #expect(ToolActivity.describe(toolName: "", input: [:]) == nil)
    }

    /// 도구 입력에 중첩 객체가 와도 문자열 필드만 걸러 쓴다(크래시 없이).
    @Test func nestedToolInputIsIgnoredGracefully() {
        let payload = ClaudeHookPayload.parse(Data(#"{"tool_name":"Edit","tool_input":{"file_path":"/a/B.swift","edits":[{"x":1}]}}"#.utf8))
        #expect(payload?.toolInput == ["file_path": "/a/B.swift"])
        #expect(ToolActivity.describe(toolName: payload?.toolName, input: payload?.toolInput ?? [:]) == "편집 중: B.swift")
    }
}
