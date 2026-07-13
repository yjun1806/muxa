import Foundation

/// 세션 transcript(JSONL)의 **꼬리**에서 마지막 assistant 메시지를 뽑는다.
///
/// "완료" 알림 본문을 `Claude가 마지막으로 한 말`로 채우기 위한 경로다. 전체 파일을 파싱하지 않는다 —
/// 긴 세션의 JSONL은 수십 MB까지 간다. 끝에서 `tailBytes`만 읽고 줄 단위로 거슬러 올라간다.
enum TranscriptTail {
    /// 파일 끝에서 읽는 최대 바이트. 마지막 assistant 메시지 한 개를 찾기엔 넉넉하다.
    static let tailBytes = 256 * 1024
    /// Stop 훅이 JSONL flush보다 먼저 도착하는 레이스가 있다 — 짧게 재시도한다.
    static let retryCount = 5
    static let retryDelay: TimeInterval = 0.05

    /// 꼬리 텍스트에서 마지막 assistant 텍스트를 찾는다(순수 — 파일 IO 없음).
    ///
    /// 첫 줄은 청크 경계에서 잘렸을 수 있으므로 JSON 파싱이 실패하면 그냥 건너뛴다(관대하게).
    /// 각 줄은 `{"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}` 꼴이다.
    static func lastAssistantMessage(inTail tail: String) -> String? {
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  root["type"] as? String == "assistant",
                  let message = root["message"] as? [String: Any],
                  let text = extractText(message["content"]),
                  !text.isEmpty
            else { continue }
            return text
        }
        return nil
    }

    /// content는 문자열이거나 블록 배열이다. 블록이면 text 타입만 이어 붙인다(tool_use 블록은 버린다).
    private static func extractText(_ content: Any?) -> String? {
        if let text = content as? String { return trimmed(text) }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text", let text = block["text"] as? String else { return nil }
            return text
        }
        return trimmed(texts.joined(separator: " "))
    }

    private static func trimmed(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 파일 꼬리를 읽어 마지막 assistant 메시지를 찾는다(경계 — 파일 IO).
    /// flush 레이스 때문에 최대 `retryCount`번 재시도한다. **호출자는 백그라운드 큐에서 부른다**
    /// (재시도가 sleep을 쓴다 — 메인 큐에서 부르면 UI가 멈춘다).
    static func lastAssistantMessage(atPath path: String) -> String? {
        for attempt in 0..<retryCount {
            if let tail = readTail(path), let message = lastAssistantMessage(inTail: tail) { return message }
            if attempt < retryCount - 1 { Thread.sleep(forTimeInterval: retryDelay) }
        }
        return nil
    }

    /// 파일 끝에서 최대 tailBytes를 읽는다. UTF-8 경계가 깨질 수 있어 손실 허용 디코딩을 쓴다.
    private static func readTail(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
