import Foundation

/// A-1 소스 읽기 — `muxa-notify statusline` sink가 떨군 `latest.json`을 `StatusLine` 스냅샷으로 읽는다.
///
/// sink는 `{observedAt, rate_limits}`만 담는다(session_id·cost 등은 안 담음). `observedAt`은 여기서 읽고,
/// 한도는 `ClaudeUsage.parseStatusLine`이 `rate_limits`를 정규화한다 — A-2와 같은 `UsageLimit` 타입이라
/// 뷰는 출처를 모른다. 파일이 없거나(미설치·콜드스타트) 깨졌으면 nil → selector가 A-2로 폴백한다.
enum StatusLineUsageStore {
    /// sink가 쓰는 경로와 동일(`MuxaSupportDir.sharedURL`은 앱·헬퍼가 같은 규칙으로 계산한다).
    static var latestURL: URL {
        MuxaSupportDir.sharedURL
            .appendingPathComponent("statusline", isDirectory: true)
            .appendingPathComponent("latest.json")
    }

    static func load() -> UsageSourceSelector.StatusLine? {
        guard let data = try? Data(contentsOf: latestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observedAt = root["observedAt"] as? Double else { return nil }
        return UsageSourceSelector.StatusLine(
            observedAt: Date(timeIntervalSince1970: observedAt),
            limits: ClaudeUsage.parseStatusLine(data))
    }
}
