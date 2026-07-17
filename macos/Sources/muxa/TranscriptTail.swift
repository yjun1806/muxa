import Foundation

/// transcript 꼬리에서 뽑은 마지막 **진짜 user 프롬프트**(순수 값) —
/// 백그라운드 팝오버(❯ 내 지시)와 사이드바 hover 팝오버가 읽는다.
struct TranscriptUserMessage: Equatable {
    /// 텍스트 블록을 이어 붙인 본문(이미지만 던진 턴이면 빈 문자열).
    let text: String
    /// image 블록 수 — 칩("이미지 N")과 hover 미리보기 로드 여부를 정한다.
    let imageCount: Int
}

/// 세션 transcript(JSONL)의 **꼬리**에서 마지막 assistant/user 메시지를 뽑는다.
///
/// assistant는 "완료" 알림 본문(`Claude가 마지막으로 한 말`), user는 "내가 마지막에 뭘 시켰나"
/// (사이드바 행 제목·백그라운드 팝오버)의 출처다. 전체 파일을 파싱하지 않는다 —
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

    // MARK: 마지막 user 프롬프트

    /// 꼬리 텍스트에서 마지막 **진짜 user 프롬프트**를 찾는다(순수 — 파일 IO 없음).
    ///
    /// user 줄이라고 다 사람의 지시가 아니다 — 도구 결과(tool_result)·시스템 삽입(isMeta)·
    /// 서브에이전트 대화(isSidechain)·슬래시 명령 배관(`<command-…>`)은 전부 건너뛴다.
    static func lastUserMessage(inTail tail: String) -> TranscriptUserMessage? {
        guard let blocks = lastUserContent(inTail: tail) else { return nil }
        return TranscriptUserMessage(text: clampPrompt(joinedText(blocks)),
                                     imageCount: imageBlocks(blocks).count)
    }

    /// 표시 상한 — 거대 붙여넣기(수십 KB)가 팝오버 행·hover 카드로 그대로 흐르면 카드가 화면보다
    /// 커진다. 상한은 훅 경로와 한 곳(`AgentPrompt.textMax`)을 쓴다 — 두 경로의 잘림이 같아야 한다.
    private static func clampPrompt(_ text: String) -> String {
        text.count <= AgentPrompt.textMax ? text : String(text.prefix(AgentPrompt.textMax)) + "…"
    }

    /// 마지막 user 프롬프트에 첨부된 이미지들(base64 디코딩) — hover 미리보기용, 최대 `limit`개.
    /// **마지막 메시지의 것만** 돌려준다 — 이전 턴의 이미지가 새면 "그 스크린샷"이 뒤바뀐다.
    static func lastUserImages(inTail tail: String, limit: Int) -> [Data] {
        guard let blocks = lastUserContent(inTail: tail) else { return [] }
        return imageBlocks(blocks).prefix(limit).compactMap { block in
            guard let source = block["source"] as? [String: Any],
                  source["type"] as? String == "base64",
                  let encoded = source["data"] as? String
            else { return nil }
            return Data(base64Encoded: encoded)
        }
    }

    /// 마지막 진짜 user 줄의 content 블록들 — 문자열 content는 text 블록 하나로 정규화한다.
    private static func lastUserContent(inTail tail: String) -> [[String: Any]]? {
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  root["type"] as? String == "user",
                  root["isMeta"] as? Bool != true,
                  root["isSidechain"] as? Bool != true,
                  let message = root["message"] as? [String: Any]
            else { continue }
            let blocks = normalizedBlocks(message["content"])
            guard isRealPrompt(blocks) else { continue }
            return blocks
        }
        return nil
    }

    private static func normalizedBlocks(_ content: Any?) -> [[String: Any]] {
        if let text = content as? String { return [["type": "text", "text": text]] }
        return content as? [[String: Any]] ?? []
    }

    /// 사람의 지시인가 — 도구 결과·슬래시 명령 배관·빈 내용은 아니다.
    private static func isRealPrompt(_ blocks: [[String: Any]]) -> Bool {
        guard !blocks.isEmpty,
              !blocks.contains(where: { $0["type"] as? String == "tool_result" })
        else { return false }
        let text = joinedText(blocks)
        if text.hasPrefix("<command-") || text.hasPrefix("<local-command") { return false }
        return !text.isEmpty || !imageBlocks(blocks).isEmpty
    }

    private static func joinedText(_ blocks: [[String: Any]]) -> String {
        blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imageBlocks(_ blocks: [[String: Any]]) -> [[String: Any]] {
        blocks.filter { $0["type"] as? String == "image" }
    }

    // MARK: 파일 경계

    /// 파일 꼬리를 읽어 마지막 assistant 메시지를 찾는다(경계 — 파일 IO).
    static func lastAssistantMessage(atPath path: String) async -> String? {
        await retryingTail(path) { lastAssistantMessage(inTail: $0) }
    }

    /// 파일 꼬리를 읽어 마지막 user 프롬프트를 찾는다(경계 — 파일 IO).
    static func lastUserMessage(atPath path: String) async -> TranscriptUserMessage? {
        await retryingTail(path) { lastUserMessage(inTail: $0) }
    }

    /// 파일 꼬리에서 마지막 user 프롬프트의 이미지들을 읽는다 — 이미지가 있다고 알 때만 부른다
    /// (없으면 재시도 지연만 낭비한다).
    static func lastUserImages(atPath path: String, limit: Int) async -> [Data] {
        await retryingTail(path) { tail in
            let images = lastUserImages(inTail: tail, limit: limit)
            return images.isEmpty ? nil : images
        } ?? []
    }

    /// 꼬리 읽기 + 추출을 재시도로 감싼다 — 훅이 JSONL flush보다 먼저 도착하는 레이스가 있다.
    /// 대기는 반드시 `Task.sleep`이어야 한다 — `Thread.sleep`은 코어 수만큼뿐인 Swift 협조
    /// 스레드풀을 붙잡아 다른 백그라운드 작업을 통째로 밀리게 한다.
    private static func retryingTail<T>(_ path: String, extract: (String) -> T?) async -> T? {
        for attempt in 0..<retryCount {
            if let tail = readTail(path), let value = extract(tail) { return value }
            if attempt < retryCount - 1 {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
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
