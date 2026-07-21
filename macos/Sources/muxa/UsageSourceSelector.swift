import Foundation

/// 사용량 소스 우선순위 판정 — **순수**. A-1(statusLine 파일)·A-2(OAuth API)·A-3(PTY)를 계층화한다.
///
/// 핵심: A-1이 신선하고 창이 유효하면 그 값을 쓰고 **A-2 프로브를 아예 건너뛴다** — 이게 429 회피의
/// 요체다. claude가 코딩하며 받은 rate_limits를 재활용하므로 사용량용 추가 요청이 0회다.
/// A-1이 없거나 낡으면 기존 A-2 경로(`UsageCoordinator.plan`)로 넘긴다 — 그건 그대로 살아 있다.
///
/// 파일 IO·네트워크는 경계(`ClaudeUsageService`)가, A-2 프로브 세부 판정은 `UsageCoordinator`가 맡는다.
enum UsageSourceSelector {
    /// A-1 소스의 신선한 스냅샷 — 관찰 시각과 정규화된 한도.
    struct StatusLine: Equatable {
        /// sink가 stdin을 마지막으로 기록한 시각(= claude가 마지막으로 rate_limits를 관찰한 때).
        let observedAt: Date
        /// `ClaudeUsage.parseStatusLine`이 정규화한 한도들(비어 있을 수 있다).
        let limits: [UsageLimit]
    }

    /// 어느 소스를 쓸지.
    enum Source: Equatable {
        /// A-1이 신선하다 — 이 값을 그대로 쓰고 A-2 프로브는 건너뛴다.
        case statusLine([UsageLimit])
        /// A-1이 없거나 낡았다 — 기존 A-2 경로로 넘긴다.
        case api
    }

    /// A-1을 쓸지, A-2로 넘길지.
    ///
    /// **`.api`로 넘기는 조건** — 하나라도 참이면 API로(보수적으로 판단한다):
    ///  1) statusLine 스냅샷이 없다 — 콜드스타트·API키 사용자·sink 미설치.
    ///  2) 표시할 한도가 없다 — `rate_limits`가 비어 왔다(첫 API 응답 전).
    ///  3) `observedAt`이 `freshFor`보다 오래됐다 — claude가 오래 유휴해 값이 낡았다.
    ///  4) 리셋 시각이 이미 지난 창이 있다 — 창이 리셋됐는데 percent는 옛값이다. A-2로 실측한다.
    ///
    /// `resetsAt == nil`(리셋 시각 파싱 실패)은 percent 자체는 유효하므로 통과시킨다.
    static func pick(statusLine: StatusLine?, now: Date, freshFor: TimeInterval) -> Source {
        guard let snapshot = statusLine, !snapshot.limits.isEmpty else { return .api }
        guard now.timeIntervalSince(snapshot.observedAt) < freshFor else { return .api }
        let anyWindowExpired = snapshot.limits.contains { limit in
            guard let resetsAt = limit.resetsAt else { return false }
            return resetsAt <= now
        }
        return anyWindowExpired ? .api : .statusLine(snapshot.limits)
    }
}
