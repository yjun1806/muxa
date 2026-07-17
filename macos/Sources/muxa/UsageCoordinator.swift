import Foundation

/// 공유 스냅샷을 보고 "지금 프로브할까, 캐시를 그대로 쓸까"를 정하는 순수 판정.
/// 부작용 없음 — 파일 IO는 `UsageCacheStore`, 상태 소유는 `ClaudeUsageService`.
enum UsageCoordinator {
    /// 뷰가 즉시 반영할 해석 결과 — 프로브 없이도 공유 캐시 값을 화면에 얹는다.
    struct Resolution: Equatable {
        let limits: [UsageLimit]
        let state: UsageState
        let lastSuccess: Date?
        let rateLimitedUntil: Date?
    }

    /// 자동 재조회 판정 결과.
    enum Plan: Equatable {
        /// 프로브하지 말고 이 값을 그대로 보여라(신선한 성공 캐시이거나 차단 중).
        case serve(Resolution)
        /// 캐시가 만료됐고 차단도 없다 — 지금 조회한다.
        case probe
    }

    /// `refreshIfStale`의 판정 — 아무 인스턴스도 최근에 조회하지 않았을 때만 프로브.
    /// `busy`는 라이브 claude 세션이 도는 중인지 — 그러면 재조회 간격을 `busyInterval`까지 늘려
    /// 그 세션들과 엔드포인트 예산을 두고 겹치지 않게 한다(상한이 유한해 굳지는 않는다).
    static func plan(snapshot: UsageSnapshot?, now: Date, policy: UsagePolicy, busy: Bool = false) -> Plan {
        guard let snapshot else { return .probe } // 아무도 조회한 적 없음
        if let until = snapshot.blockedUntil, now < until {
            return .serve(resolve(snapshot, now: now)) // 차단 중(inflight·실패·429)
        }
        let freshWindow = busy ? policy.busyInterval : policy.successInterval
        if let updated = snapshot.updatedAt,
           now.timeIntervalSince(updated) < freshWindow,
           snapshot.state == "ok" || snapshot.state == "empty" {
            return .serve(resolve(snapshot, now: now)) // 신선한 성공 캐시(라이브 세션 중이면 더 오래 유효)
        }
        return .probe
    }

    /// 스냅샷 → 뷰 상태. 차단 사유가 있으면 실패/제한으로, 아니면 마지막 성공 결과로 읽는다.
    static func resolve(_ snapshot: UsageSnapshot, now: Date) -> Resolution {
        let limits = snapshot.limits.map(\.model)
        if let until = snapshot.blockedUntil, now < until {
            switch snapshot.blockedReason {
            case "ratelimited":
                return Resolution(limits: limits, state: .rateLimited,
                                  lastSuccess: snapshot.updatedAt, rateLimitedUntil: until)
            case "failed":
                return Resolution(limits: limits, state: .failed,
                                  lastSuccess: snapshot.updatedAt, rateLimitedUntil: nil)
            default: // inflight — 마지막으로 알던 값을 그대로
                return Resolution(limits: limits, state: successState(snapshot),
                                  lastSuccess: snapshot.updatedAt, rateLimitedUntil: nil)
            }
        }
        return Resolution(limits: limits, state: successState(snapshot),
                          lastSuccess: snapshot.updatedAt, rateLimitedUntil: nil)
    }

    /// 조회 결과 → 새 스냅샷(순수). 성공은 데이터를 갈아끼우고, 실패·429는 이전 데이터를 보존한 채 차단만 얹는다.
    static func reduce(base: UsageSnapshot?, result: UsageFetch, now: Date,
                       policy: UsagePolicy) -> UsageSnapshot {
        switch result {
        case .ok(let fetched):
            // 성공하면 실패 스트릭을 지운다(failureStreak=nil) — 다음 순단은 다시 짧은 백오프부터.
            return UsageSnapshot(updatedAt: now, limits: fetched.map(PersistedLimit.init),
                                 state: "ok", blockedUntil: nil, blockedReason: nil)
        case .empty:
            // 서버는 정상 응답했다 — 갱신 시각으로는 유효하되 표시할 항목은 없다.
            return UsageSnapshot(updatedAt: now, limits: [], state: "empty",
                                 blockedUntil: nil, blockedReason: nil)
        case .rateLimited(let retryAfter):
            // 서버가 준 retry-after를 존중하되 하한(실패 백오프)·상한(1시간)으로 가둔다.
            let wait = min(max(retryAfter ?? policy.rateLimitDefault, policy.failureWait), policy.rateLimitMax)
            return (base ?? .blank).blocking(until: now.addingTimeInterval(wait), reason: "ratelimited")
        case .failure:
            // 연속 실패는 백오프를 지수로 늘린다(×2) — successInterval까지만. 순단 루프가 예산을 갉지 않게.
            let streak = (base?.failureStreak ?? 0) + 1
            let wait = min(policy.failureWait * pow(2, Double(streak - 1)), policy.successInterval)
            var next = (base ?? .blank).blocking(until: now.addingTimeInterval(wait), reason: "failed")
            next.failureStreak = streak
            return next
        }
    }

    /// 마지막 성공 결과의 뷰 상태 — 성공한 적 없으면 idle(조회 전).
    private static func successState(_ snapshot: UsageSnapshot) -> UsageState {
        if snapshot.state == "empty" { return .empty }
        if snapshot.updatedAt == nil { return .idle }
        return .ok
    }
}
