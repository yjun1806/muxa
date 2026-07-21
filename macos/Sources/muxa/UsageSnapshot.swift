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
    /// 연속 실패 횟수 — 실패 백오프를 지수로 늘리는 근거(성공·빈응답이면 0으로 리셋).
    /// 옵셔널이라 이 필드가 없던 옛 캐시 파일도 그대로 디코드된다(nil = 0).
    var failureStreak: Int?

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
    /// 성공 후 재조회 간격. `/api/oauth/usage`는 **요청 예산이 빡빡한** 비공개 엔드포인트라(사용량은
    /// 정보성일 뿐이므로) 자주 두드리면 429가 난다 — 실측: 계정 사용량이 바닥(9%)인데도 폴링만으로 제한됐다.
    /// 그래서 신선도보다 최근 스냅샷 유지를 택해 **15분**으로 둔다(orca도 같은 엔드포인트를 15분으로 폴링).
    let successInterval: TimeInterval
    /// 실패 후 **첫** 재시도 간격. 성공과 같은 15분을 쓰면 순단 한 번이 15분간의 "—"로 굳는다.
    /// 연속 실패는 이 값에서 지수로 늘어(×2) `successInterval`까지 가둔다 — 순단 루프가 예산을 갉지 않게.
    let failureWait: TimeInterval
    /// 429인데 retry-after 헤더가 없을 때의 기본 대기 — 일반 실패보다 훨씬 보수적으로.
    let rateLimitDefault: TimeInterval
    /// retry-after 상한 — 서버가 터무니없는 값을 줘도 "영영 안 물어봄"으로 굳지 않게.
    let rateLimitMax: TimeInterval
    /// single-flight 창 — 한 인스턴스가 조회를 claim한 뒤 이 시간 동안 다른 인스턴스는 프로브를 미룬다.
    let singleFlight: TimeInterval
    /// 라이브 claude 세션이 도는 동안의 재조회 간격(> `successInterval`). 그 세션들이 자기 `/status`용으로
    /// 같은 엔드포인트를 이미 두드려 예산을 나눠 쓰므로, muxa 칩은 이 상한까지 조회를 미뤄 얹지 않는다.
    /// 상한이 유한해 **영영 굳지는 않는다**(작업이 계속돼도 이 간격마다 한 번은 갱신).
    let busyInterval: TimeInterval
    /// A-1(statusLine) 값을 신선하다고 볼 상한. claude가 이 시간 안에 응답을 받았으면 그 값을 쓰고
    /// A-2 프로브를 건너뛴다(429 회피). 넘으면(긴 유휴) A-2로 교차확인한다. 판정은 `UsageSourceSelector.pick`.
    let statusLineFresh: TimeInterval

    static let live = UsagePolicy(successInterval: 900, failureWait: 120,
                                  rateLimitDefault: 900, rateLimitMax: 3600, singleFlight: 30,
                                  busyInterval: 1800, statusLineFresh: 600)
}
