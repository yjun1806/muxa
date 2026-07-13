import Foundation

/// 사용량 한도 하나 — 5시간 창·주간 전체·모델 스코프(Fable 등) 중 하나.
struct UsageLimit: Equatable, Identifiable {
    /// 한도 종류 — 서버가 준 `kind` 그대로(session · weekly_all · weekly_scoped …).
    /// 뷰가 라벨 문자열로 종류를 짐작하지 않도록 값으로 들고 다닌다.
    let kind: String
    /// 표시 라벨 — "5h" · "wk" · 모델명(Fable).
    let label: String
    /// 소진율 0~100.
    let percent: Int
    /// 한도가 리셋되는 시각. 파싱 실패면 nil.
    let resetsAt: Date?
    /// 서버가 매긴 심각도 — "normal" 외(warning 등)면 색으로 경고한다.
    let severity: String
    /// 특정 모델에만 걸린 한도(Fable 등) — 상태바에선 감추고 팝오버에서만 보여준다.
    let isModelScoped: Bool

    var id: String { label }
    var isWarning: Bool { severity != "normal" }
    /// 5시간 세션 창 — 실사용에서 가장 자주 부딪히는 한도라 리셋 시각을 상태바에 띄운다.
    var isSession: Bool { kind == "session" }
}

/// Claude 사용량 응답 파싱 — 순수 로직(네트워크·키체인은 `ClaudeUsageService`가 맡는다).
///
/// 출처는 Claude Code가 쓰는 비공식 엔드포인트 `GET /api/oauth/usage`다.
/// 공개 API가 아니라 **언제든 스키마가 바뀔 수 있다** — 파싱이 실패해도 빈 배열을 돌려줄 뿐
/// 앱 동작에는 영향을 주지 않는다(상태바에 사용량이 안 뜰 뿐).
enum ClaudeUsage {
    /// 응답의 `limits` 배열만 읽는다.
    /// 최상위 `five_hour`/`seven_day` 키와 같은 값이면서 모델 스코프(Fable)까지 한 배열에 들어 있어,
    /// 여기만 보면 표시할 항목이 전부 나온다.
    static func parse(_ data: Data) -> [UsageLimit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["limits"] as? [[String: Any]] else { return [] }
        return limits.compactMap(limit(from:))
    }

    private static func limit(from raw: [String: Any]) -> UsageLimit? {
        guard let kind = raw["kind"] as? String,
              let percent = raw["percent"] as? NSNumber else { return nil } // 서버가 9 또는 9.0으로 보낸다
        let scope = raw["scope"] as? [String: Any]
        return UsageLimit(
            kind: kind,
            label: label(kind: kind, scope: scope),
            percent: Int(percent.doubleValue.rounded()),
            resetsAt: date(from: raw["resets_at"]),
            severity: raw["severity"] as? String ?? "normal",
            // 모델이 붙은 한도 = 특정 모델 전용(Fable 등). kind 이름이 아니라 scope 유무로 판단해
            // 서버가 새 스코프 종류를 추가해도 상태바가 시끄러워지지 않는다.
            isModelScoped: (scope?["model"] as? [String: Any]) != nil
        )
    }

    /// 상태바에 띄울 한도 — 모델 전용 한도(Fable 등)는 뺀다.
    /// 항상 보이는 자리라 "세션·주간"처럼 계정 전체에 걸리는 것만 남기고, 나머지는 팝오버에서 본다.
    static func statusBar(_ limits: [UsageLimit]) -> [UsageLimit] {
        limits.filter { !$0.isModelScoped }
    }

    /// 한도 종류 → 짧은 라벨. 모델 스코프는 모델명을 그대로 쓴다(Fable 등).
    /// 모르는 kind가 와도 버리지 않고 그대로 보여준다 — 서버가 항목을 늘려도 조용히 사라지지 않게.
    static func label(kind: String, scope: [String: Any]?) -> String {
        switch kind {
        case "session": return "5h"
        case "weekly_all": return "wk"
        case "weekly_scoped":
            let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
            return model ?? "모델"
        default: return kind
        }
    }

    /// ISO8601(소수점 초 포함/미포함 둘 다) 또는 unix 초 → Date.
    static func date(from value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    /// 리셋까지 남은 시간 — "1일 3시간 후" · "3시간 38분 후" · "12분 후".
    /// 큰 단위 두 개까지만 쓴다(주간 한도는 날이 단위라 분까지 보여줘 봐야 소음이다).
    /// 이미 지났거나 모르면 nil.
    static func resetText(_ resetsAt: Date?, now: Date) -> String? {
        guard let (days, hours, minutes) = remaining(resetsAt, now: now) else { return nil }
        if days > 0 { return "\(days)일 \(hours)시간 후" }
        if hours > 0 { return "\(hours)시간 \(minutes)분 후" }
        return "\(minutes)분 후"
    }

    /// 좁은 곳(상태바)용 짧은 형태 — "1d 3h" · "3h 38m" · "12m".
    static func resetShort(_ resetsAt: Date?, now: Date) -> String? {
        guard let (days, hours, minutes) = remaining(resetsAt, now: now) else { return nil }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// 리셋되는 실제 시각 — "오후 3:39"(사용자 로케일). 날짜가 다르면 날짜도 붙인다.
    static func resetClock(_ resetsAt: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let sameDay = calendar.isDate(resetsAt, inSameDayAs: now)
        return (sameDay ? timeFormatter : dateTimeFormatter).string(from: resetsAt)
    }

    /// DateFormatter는 생성 비용이 커서 재사용한다(팝오버가 렌더마다 3번 부른다).
    private static let timeFormatter = formatter(withDate: false)
    private static let dateTimeFormatter = formatter(withDate: true)

    private static func formatter(withDate: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateStyle = withDate ? .short : .none
        f.timeStyle = .short
        return f
    }

    /// 남은 시간을 일·시·분으로. 이미 지났거나 모르면 nil.
    private static func remaining(_ resetsAt: Date?, now: Date) -> (days: Int, hours: Int, minutes: Int)? {
        guard let resetsAt else { return nil }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        return (seconds / 86400, (seconds % 86400) / 3600, (seconds % 3600) / 60)
    }
}
