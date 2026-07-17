import Foundation

/// 인스턴스 간 공유되는 사용량 좌표 — 릴리스·개발·워크트리 빌드가 **한 파일**을 함께 읽고 쓴다.
///
/// 왜 공유하나: muxa가 여러 개 동시에 뜨는데(워크트리별 개발빌드 + 릴리스) 각자 `/api/oauth/usage`를
/// 따로 두드리면, A가 429 백오프 중일 때 B의 프로브가 리밋 창을 계속 연장시켜 **아무도 못 빠져나온다**
/// (실측). 백오프·성공 캐시·single-flight를 파일 하나로 공유해 전체 요청률을 한 인스턴스분으로 낮춘다.
///
/// 순수 값 타입 — 파일 IO는 `UsageCacheStore`, 판정은 `UsageCoordinator`가 맡는다.
struct UsageSnapshot: Codable, Equatable {
    var version: Int = 1
    /// 마지막 **성공** 조회 시각(성공 캐시 TTL 기준). 아직 성공한 적 없으면 nil.
    var updatedAt: Date?
    /// 마지막 성공 시점의 한도 값 — 실패·레이트리밋 중에도 이전 값을 보여주려고 보존한다.
    var limits: [PersistedLimit]
    /// 마지막 성공의 결과 종류 — "ok" | "empty" | "" (아직 성공 없음).
    var state: String
    /// 재조회를 막는 시각. 이 시각 전에는 아무 인스턴스도 프로브하지 않는다.
    /// inflight(다른 인스턴스가 조회 중)·failed(실패 백오프)·ratelimited(429) 공용.
    var blockedUntil: Date?
    /// 차단 사유 — "inflight" | "failed" | "ratelimited". 뷰가 실패와 제한을 구분하는 근거.
    var blockedReason: String?

    /// 아무도 아직 조회하지 않은 초기 상태.
    static let blank = UsageSnapshot(updatedAt: nil, limits: [], state: "",
                                     blockedUntil: nil, blockedReason: nil)

    /// 성공 데이터(updatedAt·limits·state)는 그대로 두고 차단 창만 얹은 복사본.
    /// 실패·레이트리밋·inflight가 공유하는 규칙 — 이전 값을 지우지 않는다.
    func blocking(until: Date, reason: String) -> UsageSnapshot {
        var copy = self
        copy.blockedUntil = until
        copy.blockedReason = reason
        return copy
    }
}

/// 지속 저장용 한도 — `UsageLimit`의 Codable 미러(Date는 epoch로 직렬화된다).
struct PersistedLimit: Codable, Equatable {
    let kind: String
    let label: String
    let percent: Int
    let resetsAt: Date?
    let severity: String
    let isModelScoped: Bool

    init(_ limit: UsageLimit) {
        kind = limit.kind
        label = limit.label
        percent = limit.percent
        resetsAt = limit.resetsAt
        severity = limit.severity
        isModelScoped = limit.isModelScoped
    }

    var model: UsageLimit {
        UsageLimit(kind: kind, label: label, percent: percent, resetsAt: resetsAt,
                   severity: severity, isModelScoped: isModelScoped)
    }
}

/// 백오프·캐시 간격 — 기존 `ClaudeUsageService` 상수를 순수 함수가 쓰도록 값으로 묶는다.
struct UsagePolicy {
    /// 성공 후 재조회 간격. 사용량 API를 자주 때리면 계정에 이상 신호가 될 수 있어 캐시로 막는다.
    let successInterval: TimeInterval
    /// 실패 후 재시도 간격. 성공과 같은 5분을 쓰면 순단 한 번이 5분간의 "—"로 굳는다.
    let failureWait: TimeInterval
    /// 429인데 retry-after 헤더가 없을 때의 기본 대기 — 일반 실패보다 훨씬 보수적으로.
    let rateLimitDefault: TimeInterval
    /// retry-after 상한 — 서버가 터무니없는 값을 줘도 "영영 안 물어봄"으로 굳지 않게.
    let rateLimitMax: TimeInterval
    /// single-flight 창 — 한 인스턴스가 조회를 claim한 뒤 이 시간 동안 다른 인스턴스는 프로브를 미룬다.
    let singleFlight: TimeInterval

    static let live = UsagePolicy(successInterval: 300, failureWait: 45,
                                  rateLimitDefault: 900, rateLimitMax: 3600, singleFlight: 30)
}
