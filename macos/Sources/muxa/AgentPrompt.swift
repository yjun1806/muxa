import Foundation

/// 사용자가 마지막으로 입력한 프롬프트(순수 값) — `UserPromptSubmit` 훅의 `prompt` 필드에서 온다.
///
/// 사이드바 에이전트 행의 **제목**(프롬프트가 곧 행의 이름)과 hover 팝오버(전문·이미지 수)가 읽는다.
/// 붙여넣은 이미지는 본문에 "[Image #N]" 마커로 들어오므로 개수로 접고 본문에서는 뺀다.
struct AgentPrompt: Equatable {
    /// 전문(마커 제거·앞뒤 공백 정리, 최대 `textMax`자) — hover 팝오버가 개행 그대로 보여준다.
    let text: String
    /// 첨부 이미지 수("[Image #N]" 마커 개수).
    let imageCount: Int
    /// 저장 시점에 잘렸는가 — 팝오버가 "…"의 의미(더 있음)를 안다.
    let truncated: Bool

    /// 전문 상한 — 수백 KB 붙여넣기가 탭마다 메모리에 남지 않게. 팝오버 표시로는 충분한 길이.
    static let textMax = 500

    /// 행 제목용 한 줄 — 개행·연속 공백을 공백 하나로 접는다.
    var oneLine: String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 원문 프롬프트를 파싱한다. 텍스트도 이미지도 없으면 nil — 빈 행 제목을 만들지 않는다.
    static func parse(_ raw: String?) -> AgentPrompt? {
        guard let raw, !raw.isEmpty else { return nil }
        let marker = #/\[Image #\d+\]/#
        let imageCount = raw.matches(of: marker).count
        let stripped = raw.replacing(marker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty || imageCount > 0 else { return nil }
        let truncated = stripped.count > textMax
        let text = truncated ? String(stripped.prefix(textMax)) + "…" : stripped
        return AgentPrompt(text: text, imageCount: imageCount, truncated: truncated)
    }
}
