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

    init(fetcher: @escaping @Sendable () async -> UsageFetch = ClaudeUsageService.liveFetch,
         now: @escaping @Sendable () -> Date = Date.init,
         store: any UsageStore = UsageFileStore.default,
         policy: UsagePolicy = .live) {
        self.fetcher = fetcher
        self.now = now
        self.store = store
        self.policy = policy
    }

    var failed: Bool { state == .failed }
    /// 마지막 갱신이 실패(레이트리밋 포함) — 칩이 "지금 보이는 건 이전 값" 경고를 띄우는 기준.
    var stale: Bool { state == .failed || state == .rateLimited }

    /// 캐시가 만료됐을 때만 조회. 판정은 **공유 스냅샷**을 근거로 내린다 — 다른 muxa 인스턴스가
    /// 방금 성공했거나(캐시 서빙) 429를 받았으면(백오프 존중) 이 인스턴스는 네트워크를 아예 건드리지 않는다.
    func refreshIfStale() async {
        guard !loading else { return }
        let snapshot = store.load()
        switch UsageCoordinator.plan(snapshot: snapshot, now: now(), policy: policy) {
        case .serve(let resolution):
            apply(resolution) // 공유 캐시 값을 그대로 화면에 얹는다(프로브 없음)
        case .probe:
            await probe()
        }
    }

    /// 강제 조회(새로고침 버튼) — 사용자가 눌렀으면 백오프를 무시하고 지금 물어본다.
    func refresh() async {
        guard !loading else { return }
        await probe()
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
    static let liveFetch: @Sendable () async -> UsageFetch = {
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
