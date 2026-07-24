import Foundation

/// Claude Code IDE 통합 MCP 프로토콜의 **고정 응답·페이로드 조립**(순수). 와이어 값은 claudecode.nvim
/// 레퍼런스(플러그인 0.2.0, MCP `2024-11-05`)에서 그대로 옮겼다. 프레이밍·소켓은 IdeServer가 맡는다.
///
/// 함정 두 가지를 여기서 못 박는다: (1) 빈 객체는 `{}`(빈 dict)로 — `logging`·인자 없는 툴 결과.
/// (2) 툴 결과의 `text`는 **JSON을 담은 문자열**(이중 인코딩) — `toolText`가 담당.
enum IdeProtocol {
    static let protocolVersion = "2024-11-05"
    /// 락파일·serverInfo에 쓰는 IDE 이름 — CLI가 "Connected to <ideName>"으로 표시한다.
    static let ideName = "muxa"

    // MARK: 핸드셰이크 고정 응답

    /// `initialize` 결과. `logging`은 반드시 빈 객체 `{}`.
    static func initializeResult(version: String) -> [String: Any] {
        ["protocolVersion": protocolVersion,
         "capabilities": ["logging": [String: Any](),
                          "prompts": ["listChanged": true],
                          "tools": ["listChanged": true]],
         "serverInfo": ["name": "muxa", "version": version]]
    }

    /// `prompts/list` 결과 — 빈 배열.
    static let promptsListResult: [String: Any] = ["prompts": [Any]()]

    /// `tools/list` 결과 — CLI가 모델에 노출할 툴 목록. 스키마는 레퍼런스 그대로(draft-07).
    static var toolsListResult: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(toolsListJSON.utf8)) as? [String: Any]) ?? ["tools": [Any]()]
    }

    // MARK: 툴 결과 엔벨로프

    /// 툴 결과 `result` = `{content:[{type:text, text:<문자열>}]}`. text는 평문 또는 JSON문자열.
    static func toolResult(text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    /// 객체를 **JSON 문자열**로 직렬화(이중 인코딩용). 실패 시 빈 객체 문자열.
    static func toolText(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func toolText(array: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    // MARK: 선택(selection) 페이로드

    /// selection_changed 알림 params = 선택 객체 그 자체(0-기반 line/character).
    static func selectionParams(_ sel: IdeSelection) -> [String: Any] {
        ["text": sel.text,
         "filePath": sel.filePath,
         "fileUrl": sel.fileURL,
         "selection": ["start": ["line": sel.startLine, "character": sel.startCharacter],
                       "end": ["line": sel.endLine, "character": sel.endCharacter],
                       "isEmpty": sel.isEmpty]]
    }

    /// getCurrentSelection/getLatestSelection 툴의 text(JSON문자열). 활성 편집기가 없으면 success:false.
    static func selectionText(_ sel: IdeSelection?) -> String {
        guard let sel else { return toolText(["success": false, "message": "No active editor found"]) }
        var obj = selectionParams(sel)
        obj["success"] = true
        return toolText(obj)
    }

    /// at_mentioned 알림 params(0-기반 줄). 파일 전체면 줄 범위는 생략(nil).
    static func atMentionedParams(filePath: String, lineStart: Int?, lineEnd: Int?) -> [String: Any] {
        var p: [String: Any] = ["filePath": filePath]
        if let lineStart { p["lineStart"] = lineStart }
        if let lineEnd { p["lineEnd"] = lineEnd }
        return p
    }

    // MARK: tools/list 원본 JSON (레퍼런스 스키마 그대로)

    private static let toolsListJSON = #"""
    {"tools":[
     {"name":"openFile","description":"Open a file in the editor and optionally select a range of text","inputSchema":{"type":"object","properties":{"filePath":{"type":"string","description":"Path to the file to open"},"preview":{"type":"boolean","description":"Whether to open the file in preview mode","default":false},"startLine":{"type":"integer","description":"Optional: Line number to start selection"},"endLine":{"type":"integer","description":"Optional: Line number to end selection"},"startText":{"type":"string","description":"Text pattern to find the start of the selection range. Selects from the beginning of this match."},"endText":{"type":"string","description":"Text pattern to find the end of the selection range. Selects up to the end of this match. If not provided, only the startText match will be selected."},"selectToEndOfLine":{"type":"boolean","description":"If true, selection will extend to the end of the line containing the endText match.","default":false},"makeFrontmost":{"type":"boolean","description":"Whether to make the file the active editor tab. If false, the file will be opened in the background without changing focus.","default":true}},"required":["filePath"],"additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"getCurrentSelection","description":"Get the current text selection in the editor","inputSchema":{"type":"object","additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"getLatestSelection","description":"Get the most recent text selection (even if not in the active editor)","inputSchema":{"type":"object","additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"getOpenEditors","description":"Get list of currently open files","inputSchema":{"type":"object","additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"getWorkspaceFolders","description":"Get all workspace folders currently open in the IDE","inputSchema":{"type":"object","additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"getDiagnostics","description":"Get language diagnostics (errors, warnings) from the editor","inputSchema":{"type":"object","properties":{"uri":{"type":"string","description":"Optional file URI to get diagnostics for. If not provided, gets diagnostics for all open files."}},"additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"checkDocumentDirty","description":"Check if a document has unsaved changes (is dirty)","inputSchema":{"type":"object","properties":{"filePath":{"type":"string","description":"Path to the file to check"}},"required":["filePath"],"additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"saveDocument","description":"Save a document with unsaved changes","inputSchema":{"type":"object","properties":{"filePath":{"type":"string","description":"Path to the file to save"}},"required":["filePath"],"additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"closeAllDiffTabs","description":"Close all diff tabs in the editor","inputSchema":{"type":"object","additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}},
     {"name":"openDiff","description":"Open a diff view comparing old file content with new file content","inputSchema":{"type":"object","properties":{"old_file_path":{"type":"string","description":"Path to the old file to compare"},"new_file_path":{"type":"string","description":"Path to the new file to compare"},"new_file_contents":{"type":"string","description":"Contents for the new file version"},"tab_name":{"type":"string","description":"Name for the diff tab/view"}},"required":["old_file_path","new_file_path","new_file_contents","tab_name"],"additionalProperties":false,"$schema":"http://json-schema.org/draft-07/schema#"}}
    ]}
    """#
}
