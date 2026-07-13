import Foundation
import Observation

/// 사용량 조회 결과 — "실패"와 "응답은 왔지만 한도가 없음"을 구분한다.
/// 비공식 API를 쓰는 이상 **스키마 변경이 가장 유력한 고장 시나리오**라, 그걸 네트워크 오류와
/// 뭉뚱그리면 진단이 불가능해진다(`.empty`가 뜨면 스키마를 의심할 신호).
enum UsageFetch: Equatable {
    case ok([UsageLimit])
    /// HTTP 200인데 한도 항목이 0개 — 스키마가 바뀌었을 가능성.
    case empty
    /// 자격 증명 없음·만료, 네트워크·서버 오류.
    case failure
}

/// 사용량 표시 상태 — 뷰가 무엇을 그릴지 정하는 단일 값.
enum UsageState: Equatable {
    case idle       // 아직 한 번도 조회 안 함
    case ok
    case empty
    case failed
}

/// claude 사용량 조회 — 키체인·네트워크 부작용을 여기 한 곳에 가둔다(파싱은 순수 `ClaudeUsage`).
///
/// 동작: macOS 키체인의 `Claude Code-credentials`(Claude Code가 로그인 시 저장)에서 OAuth 액세스 토큰을
/// 읽어 `GET /api/oauth/usage`를 호출한다. 토큰은 이 호출에만 쓰고 로그·디스크에 남기지 않는다.
///
/// **토큰 갱신(refresh)은 하지 않는다.** 만료면 조용히 실패 표시만 한다 — 돌고 있는 claude 세션이
/// 토큰을 회전시키는 중에 muxa가 끼어들면 서로 덮어써 로그인이 깨질 수 있다. 갱신은 claude에게 맡긴다.
///
/// 조회(네트워크·키체인)와 시각(now)은 주입 가능하다 — 캐시·백오프 규칙을 테스트로 검증하기 위해서다.
@MainActor
@Observable
final class ClaudeUsageService {
    static let shared = ClaudeUsageService()

    private(set) var limits: [UsageLimit] = []
    private(set) var state: UsageState = .idle
    private(set) var loading = false
    /// 마지막 **성공** 시각 — 팝오버가 "N분 전 갱신"으로 보여준다.
    private(set) var lastSuccess: Date?

    /// 마지막 시도 시각(실패 포함) — 백오프 기준.
    @ObservationIgnored private var lastAttempt: Date?
    /// 성공 후 재조회 간격. 사용량 API를 자주 때리면 계정에 이상 신호가 될 수 있어 캐시로 막는다.
    @ObservationIgnored private let successInterval: TimeInterval = 300
    /// 실패 후 재시도 간격. 성공과 같은 5분을 쓰면 순단 한 번이 5분간의 "—"로 굳는다(랩탑 깨어난 직후 등).
    @ObservationIgnored private let retryInterval: TimeInterval = 45

    @ObservationIgnored private let fetcher: @Sendable () async -> UsageFetch
    @ObservationIgnored private let now: @Sendable () -> Date

    init(fetcher: @escaping @Sendable () async -> UsageFetch = ClaudeUsageService.liveFetch,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.fetcher = fetcher
        self.now = now
    }

    var failed: Bool { state == .failed }

    /// 캐시가 만료됐을 때만 조회. 마지막 결과에 따라 대기 시간이 다르다(성공 5분·실패 45초).
    func refreshIfStale() async {
        if let lastAttempt {
            let wait = state == .failed ? retryInterval : successInterval
            if now().timeIntervalSince(lastAttempt) < wait { return }
        }
        await refresh()
    }

    /// 강제 조회(새로고침 버튼).
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let result = await fetcher()
        lastAttempt = now()

        switch result {
        case .ok(let fetched):
            limits = fetched
            state = .ok
            lastSuccess = now()
        case .empty:
            limits = []
            state = .empty
            lastSuccess = now() // 서버는 정상 응답했다 — 갱신 시각으로는 유효
        case .failure:
            state = .failed // 이전 limits는 유지 — 일시적 실패로 화면이 비지 않게
        }
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
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .failure }
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
