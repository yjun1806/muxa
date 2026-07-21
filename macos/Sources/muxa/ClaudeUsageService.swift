import Foundation
import Observation

/// 사용량 조회 결과 — "실패"와 "응답은 왔지만 한도가 없음"을 구분한다.
/// 비공식 API를 쓰는 이상 **스키마 변경이 가장 유력한 고장 시나리오**라, 그걸 네트워크 오류와
/// 뭉뚱그리면 진단이 불가능해진다(`.empty`가 뜨면 스키마를 의심할 신호).
enum UsageFetch: Equatable {
    case ok([UsageLimit])
    /// HTTP 200인데 한도 항목이 0개 — 스키마가 바뀌었을 가능성.
    case empty
    /// HTTP 429 — 서버가 "기다려라"고 말했다. retry-after 헤더(초)를 그대로 존중해야 한다.
    /// 일반 실패의 45초 백오프로 두드리면 리밋 창이 계속 연장돼 스스로 벗어나지 못한다(실측).
    case rateLimited(retryAfter: TimeInterval?)
    /// 자격 증명 없음·만료, 네트워크·서버 오류.
    case failure
}

/// 사용량 표시 상태 — 뷰가 무엇을 그릴지 정하는 단일 값.
enum UsageState: Equatable {
    case idle       // 아직 한 번도 조회 안 함
    case ok
    case empty
    case failed
    case rateLimited // 서버가 요청을 제한 중 — 로그인 문제가 아니다(뷰가 구분해 안내한다)
}

/// claude 사용량 조회 — 키체인·네트워크 부작용을 여기 한 곳에 가둔다(파싱은 순수 `ClaudeUsage`).
///
/// 동작: macOS 키체인의 `Claude Code-credentials`(Claude Code가 로그인 시 저장)에서 OAuth 액세스 토큰을
/// 읽어 `GET /api/oauth/usage`를 호출한다. 토큰은 이 호출에만 쓰고 로그·디스크에 남기지 않는다.
///
/// **토큰 갱신(refresh)은 하지 않는다.** 만료면 조용히 실패 표시만 한다 — 돌고 있는 claude 세션이
/// 토큰을 회전시키는 중에 muxa가 끼어들면 서로 덮어써 로그인이 깨질 수 있다. 갱신은 claude에게 맡긴다.
///
/// **백오프·성공 캐시·single-flight는 인스턴스 간에 공유한다**(`UsageCacheStore` → `MuxaSupportDir.sharedURL`).
/// 여러 muxa가 각자 API를 두드려 리밋 창을 서로 연장시키던 자충수를 막는다 — 판정은 순수 `UsageCoordinator`.
///
/// 조회(네트워크·키체인)·시각(now)·저장소(store)는 주입 가능하다 — 캐시·백오프 규칙을 테스트로 검증하기 위해서다.
@MainActor
@Observable
final class ClaudeUsageService {
    static let shared = ClaudeUsageService()

    private(set) var limits: [UsageLimit] = []
    private(set) var state: UsageState = .idle
    private(set) var loading = false
    /// 마지막 **성공** 시각 — 팝오버가 "N분 전 갱신"으로 보여준다.
    private(set) var lastSuccess: Date?
    /// 레이트리밋 해제 예정 시각 — 팝오버가 "N분 후 자동 재시도"로 보여준다.
    private(set) var rateLimitedUntil: Date?

    /// 캐시·백오프 간격. 판정은 `UsageCoordinator`(순수)가 이 값으로 내린다.
    @ObservationIgnored private let policy: UsagePolicy

    /// 인스턴스 간 공유 스냅샷 저장소 — 백오프·성공 캐시·single-flight를 모든 빌드가 함께 본다.
    @ObservationIgnored private let store: any UsageStore

    @ObservationIgnored private let fetcher: @Sendable () async -> UsageFetch
    @ObservationIgnored private let now: @Sendable () -> Date

    /// A-1 소스 로더 — statusLine sink가 떨군 값을 읽는다(주입 가능 — 테스트용). 기본은 실제 파일.
    @ObservationIgnored private let statusLine: () -> UsageSourceSelector.StatusLine?

    init(fetcher: @escaping @Sendable () async -> UsageFetch = ClaudeUsageService.liveFetch,
         now: @escaping @Sendable () -> Date = { Date() },
         store: any UsageStore = UsageFileStore.default,
         policy: UsagePolicy = .live,
         statusLine: @escaping () -> UsageSourceSelector.StatusLine? = StatusLineUsageStore.load) {
        self.fetcher = fetcher
        self.now = now
        self.store = store
        self.policy = policy
        self.statusLine = statusLine
    }

    var failed: Bool { state == .failed }
    /// 마지막 갱신이 실패(레이트리밋 포함) — 칩이 "지금 보이는 건 이전 값" 경고를 띄우는 기준.
    var stale: Bool { state == .failed || state == .rateLimited }

    /// 캐시가 만료됐을 때만 조회. 판정은 **공유 스냅샷**을 근거로 내린다 — 다른 muxa 인스턴스가
    /// 방금 성공했거나(캐시 서빙) 429를 받았으면(백오프 존중) 이 인스턴스는 네트워크를 아예 건드리지 않는다.
    /// `busy`는 라이브 claude 세션이 도는 중인지 — 그러면 재조회를 `busyInterval`까지 미뤄
    /// 그 세션들과 사용량 엔드포인트 예산을 두고 겹치지 않게 한다(판정은 순수 `UsageCoordinator.plan`).
    func refreshIfStale(busy: Bool = false) async {
        guard !loading else { return }
        // A-1 우선 — statusLine 파일이 신선하면 그 값을 그리고 **A-2 프로브를 건너뛴다**(429 회피의 핵심).
        // claude가 코딩하며 받은 값이라 사용량용 추가 요청이 0회다. 없거나 낡으면 아래 A-2 경로로 넘어간다.
        if case .statusLine(let limits) = UsageSourceSelector.pick(
            statusLine: statusLine(), now: now(), freshFor: policy.statusLineFresh) {
            applyStatusLine(limits)
            // A-1은 Fable(모델 스코프)을 안 준다 — A-1이 계속 신선하면 Fable이 마지막 A-2 값에 굳는다.
            // 캐시가 fableRefresh보다 낡았고 A-2가 막히지 않았으면, 그것만 되살리러 딱 한 번 프로브한다.
            // (successInterval마다 태우면 429 회피 이점이 사라지므로 별도의 긴 TTL을 쓴다.)
            if fableRefreshDue(store.load()) {
                await probe()
                applyStatusLine(limits) // A-1 우선값 + 방금 갱신된 Fable로 재병합(probe가 얹은 A-2 우선값을 덮는다)
            }
            return
        }
        let snapshot = store.load()
        switch UsageCoordinator.plan(snapshot: snapshot, now: now(), policy: policy, busy: busy) {
        case .serve(let resolution):
            apply(resolution) // 공유 캐시 값을 그대로 화면에 얹는다(프로브 없음)
        case .probe:
            await probe()
        }
    }

    /// A-1(statusLine) 값을 화면에 얹는다 — 성공 상태로 취급한다(서버 권위값이다).
    /// 공유 캐시(A-2 백오프)는 건드리지 않는다 — A-1이 신선한 동안 A-2 경로는 쉬면 되고,
    /// 다른 인스턴스도 각자 같은 latest.json을 읽어 똑같이 A-2를 건너뛴다.
    ///
    /// **A-1은 five_hour/seven_day만 준다 — Fable 등 모델 스코프 한도는 없다.** 마지막 A-2 성공 캐시에서
    /// 그것들만 가져와 합친다. Fable weekly는 7일 단위라 느리게 변해 stale해도 무해하고, 이게 없으면
    /// A-1이 신선한 동안 팝오버에서 Fable이 사라진다(A-2를 건너뛰므로).
    private func applyStatusLine(_ limits: [UsageLimit]) {
        let modelScoped = (store.load()?.limits.map(\.model) ?? []).filter(\.isModelScoped)
        self.limits = limits + modelScoped
        state = .ok
        lastSuccess = now()
        rateLimitedUntil = nil
    }

    /// 모델 스코프(Fable) 캐시를 A-2로 되살릴 때가 됐나 — A-1이 신선할 때만 묻는다.
    ///
    /// **캐시에 Fable이 이미 있고 낡았을 때만** true다. 이유:
    ///  - Fable이 **아예 없으면** 프로브하지 않는다 → "A-1 신선 ⇒ API 0회" 계약을 지킨다.
    ///    최초 채움은 유휴로 A-1이 낡을 때 도는 **정상 A-2 경로**가 맡는다(그때 Fable도 함께 온다).
    ///  - A-2가 막혀 있으면(inflight·429·실패 백오프) 그 판정을 존중한다 — 실패 후 매 틱 두드리지 않게.
    private func fableRefreshDue(_ snapshot: UsageSnapshot?) -> Bool {
        if loading { return false }
        guard let snapshot, snapshot.limits.contains(where: \.isModelScoped) else { return false }
        if let until = snapshot.blockedUntil, now() < until { return false }
        guard let updated = snapshot.updatedAt else { return false }
        return now().timeIntervalSince(updated) >= policy.fableRefresh
    }

    /// 강제 조회 — 좌표 판정(백오프·429·캐시 TTL)을 **모두 우회하고** 지금 즉시 프로브한다.
    /// UI에 노출하지 않는다(모든 걸 우회해 연타=429인 풋건) — 테스트·진단 전용. 사용자용은 `manualRefresh`.
    func refresh() async {
        guard !loading else { return }
        await probe()
    }

    /// 사용자 수동 갱신 — "지금 보고 싶다". **429·연타 안전**하게 캐시 TTL만 우회한다:
    ///  - 429/실패 백오프 창 안이면 아무것도 안 한다(그 판정을 우회하면 리밋이 연장된다 — 절대 안 뚫는다).
    ///  - 마지막 성공이 `manualDebounce`(30초) 안이면 무시한다(데이터가 이미 신선 + 연타 차단).
    ///  - 그 외엔 지금 한 번 조회한다. A-1이 신선하면 Fable만 되살아나게 A-1 우선값으로 재병합한다.
    /// 반환: 실제로 조회했으면 `true`(뷰가 짧은 피드백을 줄 수 있게).
    @discardableResult
    func manualRefresh() async -> Bool {
        guard !loading else { return false }
        let snapshot = store.load()
        if let until = snapshot?.blockedUntil, now() < until { return false }        // 429/백오프 존중
        if let updated = snapshot?.updatedAt,
           now().timeIntervalSince(updated) < policy.manualDebounce { return false }  // 디바운스(연타 방지)
        await probe()
        if case .statusLine(let limits) = UsageSourceSelector.pick(
            statusLine: statusLine(), now: now(), freshFor: policy.statusLineFresh) {
            applyStatusLine(limits) // A-1이 신선하면 probe가 얹은 A-2 우선값을 A-1로 되돌린다(Fable만 갱신 효과)
        }
        return true
    }

    /// 지금 수동 갱신이 막혀 있나(429·실패 백오프 창) — 버튼을 회색으로 두고 "N분 후"를 알릴 근거.
    var manualBlockedUntil: Date? {
        guard let until = store.load()?.blockedUntil, now() < until else { return nil }
        return until
    }

    /// 실제 조회 한 번. single-flight를 claim(공유 파일에 inflight 표식)한 뒤 fetcher를 부르고,
    /// 결과를 공유 스냅샷에 반영한다 — 그동안 다른 인스턴스는 inflight를 보고 프로브를 미룬다.
    private func probe() async {
        loading = true
        defer { loading = false }

        let base = store.load()
        // claim: 프로브 직전에 inflight 창을 써 둔다. 동시에 뜬 다른 인스턴스가 겹쳐 두드리는 걸 줄인다.
        let claimedAt = now()
        store.save((base ?? .blank).blocking(until: claimedAt.addingTimeInterval(policy.singleFlight),
                                              reason: "inflight"))

        let result = await fetcher()
        let finishedAt = now()
        let next = UsageCoordinator.reduce(base: base, result: result, now: finishedAt, policy: policy)
        store.save(next)
        apply(UsageCoordinator.resolve(next, now: finishedAt))
    }

    /// 좌표 판정 결과를 관측 상태에 반영 — 뷰가 그릴 단일 값들.
    private func apply(_ resolution: UsageCoordinator.Resolution) {
        limits = resolution.limits
        state = resolution.state
        lastSuccess = resolution.lastSuccess
        rateLimitedUntil = resolution.rateLimitedUntil
    }

    // MARK: 부작용 경계 (메인 액터 밖에서 실행)

    /// 실제 조회 — 키체인 → HTTP. 기본 fetcher.
    /// `nonisolated` — 본문이 detached task + nonisolated 헬퍼(accessToken·request)뿐이라 MainActor가
    /// 필요 없고, 이게 없으면 init 기본 인자(nonisolated 평가)에서 참조할 때 Swift 6 경고가 난다.
    nonisolated static let liveFetch: @Sendable () async -> UsageFetch = {
        await Task.detached(priority: .utility) { () -> UsageFetch in
            guard let token = accessToken() else { return .failure }
            return await request(token: token)
        }.value
    }

    /// 키체인에서 액세스 토큰을 읽는다. 만료됐거나 항목이 없으면 nil.
    private nonisolated static func accessToken() -> String? {
        guard let json = keychainSecret(service: "Claude Code-credentials"),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        // expiresAt(ms)이 지났으면 갱신하지 않고 포기한다 — 갱신은 claude 몫(위 주석).
        if let expiresAt = oauth["expiresAt"] as? NSNumber,
           Date().timeIntervalSince1970 * 1000 >= expiresAt.doubleValue { return nil }
        return token
    }

    /// `security` CLI 셸아웃 — 키체인 항목 하나의 값을 읽는다(GitService의 CLI 셸아웃과 같은 패턴).
    private nonisolated static func keychainSecret(service: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 사용량 조회. 비공식 엔드포인트라 실패는 정상 경로로 취급한다.
    private nonisolated static func request(token: String) async -> UsageFetch {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return .failure }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failure }
            if http.statusCode == 429 {
                // 서버가 대기 시간을 알려준다(초). 무시하고 일반 백오프로 두드리면 리밋이 연장된다.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                NSLog("[muxa] claude usage: 429 — retry-after %@초", retryAfter.map { String(Int($0)) } ?? "미지정")
                return .rateLimited(retryAfter: retryAfter)
            }
            guard http.statusCode == 200 else { return .failure }
            let parsed = ClaudeUsage.parse(data)
            if parsed.isEmpty {
                // 200인데 항목이 0개 = 스키마가 바뀐 신호. 조용히 실패로 뭉개지 말고 남긴다.
                NSLog("[muxa] claude usage: 200이지만 한도 항목 0개 — 응답 스키마 변경 가능성")
                return .empty
            }
            return .ok(parsed)
        } catch {
            return .failure
        }
    }
}
