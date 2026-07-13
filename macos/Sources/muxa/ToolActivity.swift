import Foundation

/// 도구 호출(PreToolUse/PostToolUse)을 사람이 읽는 한 줄로 바꾸는 순수 함수.
///
/// LLM 요약을 쓰지 않는다 — 비용·지연을 알림 경로에 넣을 이유가 없다. 20줄짜리 매핑이면
/// "Edit: TermView.swift"가 즉시 나온다. 모르는 도구는 이름만 그대로 보여준다(무음보다 낫다).
enum ToolActivity {
    /// 진행 표시 한 줄. 도구 이름이 없으면 nil(표시할 게 없다).
    static func describe(toolName: String?, input: [String: String]) -> String? {
        guard let tool = toolName, !tool.isEmpty else { return nil }
        switch tool {
        case "Read":       return labeled("읽는 중", shorten(path: input["file_path"]))
        case "Edit", "Write", "NotebookEdit":
            return labeled("편집 중", shorten(path: input["file_path"]))
        case "Bash":       return labeled("실행 중", firstToken(input["command"]))
        case "Grep":       return labeled("검색 중", truncate(input["pattern"], max: patternMax))
        case "Glob":       return labeled("탐색 중", truncate(input["pattern"], max: patternMax))
        case "WebSearch":  return labeled("웹 검색", truncate(input["query"], max: patternMax))
        case "WebFetch":   return labeled("웹 읽는 중", shorten(host: input["url"]))
        case "Task", "Agent":
            return labeled("서브에이전트", truncate(input["description"], max: descriptionMax))
        default:           return tool
        }
    }

    /// 명령의 첫 토큰만(전체 명령줄은 길고 시끄럽다) — "swift build --foo" → "swift".
    private static func firstToken(_ command: String?) -> String? {
        guard let first = command?.split(separator: " ").first else { return nil }
        return truncate(String(first), max: commandMax)
    }

    /// 경로는 파일명만 — 전체 경로는 탭 폭을 넘긴다.
    private static func shorten(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// URL은 호스트만 — 쿼리스트링까지 보여줄 이유가 없다.
    private static func shorten(host: String?) -> String? {
        guard let raw = host, let url = URL(string: raw), let host = url.host else { return nil }
        return host
    }

    private static func truncate(_ text: String?, max: Int) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text.count <= max ? text : String(text.prefix(max)) + "…"
    }

    /// 인자가 없으면 라벨만 — "편집 중"이라도 "무음"보다 낫다.
    private static func labeled(_ label: String, _ argument: String?) -> String {
        guard let argument, !argument.isEmpty else { return label }
        return "\(label): \(argument)"
    }

    private static let commandMax = 30
    private static let patternMax = 30
    private static let descriptionMax = 40
}
