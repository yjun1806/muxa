import Foundation
import Observation

/// 업데이트 확인·설치의 사용자-표시 상태(경계) — 네트워크·재빌드 부작용을 여기 가두고, **판정은
/// 순수 `UpdateCheck`**가 내린다. 레일 배지·팝오버가 이 한 값(`phase`)만 읽는다.
///
/// 흐름: 실행 시 + 24h 폴링으로 GitHub 태그를 받아 `available`을 세운다 → 사용자가 누르면 `updating`
/// (백그라운드 재빌드, 화면에 안 보임) → `updated`(재시작 안내) 또는 `failed`(로그 경로). **재실행은 안 한다.**
///
/// **개발빌드는 폴링하지 않는다**(`AppInfo.isDev`) — dev 버전은 semver가 아니라 오탐만 낳는다.
/// **실패는 전부 무음**이다 — 오프라인·GitHub 다운이 UI를 막거나 배지를 띄우면 안 된다(조회 실패 시 phase 유지).
/// 조회(`fetchTags`)·설치(`install`)·시각(`now`)은 주입 가능하다 — 판정·전이를 테스트로 못 박기 위해서다.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 업데이트 상태 한 값 — 레일 배지·팝오버가 이걸 보고 그린다.
    enum Phase: Equatable {
        case idle                                   // 미확인 또는 최신 — 배지 없음
        case available(SemVer)                      // 새 버전 있음 — 배지
        case updating(SemVer)                       // 재빌드 중(백그라운드)
        case updated(SemVer)                        // 완료 — 재시작하면 적용
        case failed(SemVer, message: String, logPath: String?)  // 재빌드 실패
    }

    private(set) var phase: Phase = .idle

    /// 자동 확인 on/off — 설정 토글이 바꾼다(즉시 UserDefaults 영속). 끄면 배지가 사라진다.
    var autoCheckEnabled: Bool {
        didSet {
            defaults.set(autoCheckEnabled, forKey: Self.enabledKey)
            if !autoCheckEnabled, case .available = phase { phase = .idle }
        }
    }

    /// 폴링 간격 — 하루 1회. 릴리스 앱 하나만 폴링하므로(dev 스킵) GitHub 레이트리밋과 무관.
    static let pollInterval: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let current: String
    @ObservationIgnored private let isDev: Bool
    @ObservationIgnored private let sourceRoot: String?
    @ObservationIgnored private let fetchTags: @Sendable () async -> [String]?
    @ObservationIgnored private let install: @Sendable (String) async -> Result<Void, UpdateInstaller.Failure>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loopStarted = false

    private static let enabledKey = "muxa.update.autoCheck"

    init(current: String = AppInfo.version,
         isDev: Bool = AppInfo.isDev,
         sourceRoot: String? = AppInfo.sourceRoot,
         fetchTags: @escaping @Sendable () async -> [String]? = UpdateChecker.liveFetchTags,
         install: @escaping @Sendable (String) async -> Result<Void, UpdateInstaller.Failure> = UpdateChecker.liveInstall,
         defaults: UserDefaults = .standard) {
        self.current = current
        self.isDev = isDev
        self.sourceRoot = sourceRoot
        self.fetchTags = fetchTags
        self.install = install
        self.defaults = defaults
        // 기본 켜짐 — 설치본은 업데이트를 알 방법이 이것뿐이라 opt-out(끄기)으로 둔다.
        autoCheckEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// 앱 시작 시 1회 호출 — 즉시 확인 후 24h마다 반복한다. dev 빌드면 아무것도 안 한다.
    func startPolling() {
        guard !isDev, !loopStarted else { return }
        loopStarted = true
        Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.checkNow()
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// await(조회) 뒤에 설치 흐름이 시작됐는지 — 그렇다면 재조회 결과로 그 상태를 덮지 않는다(경쟁 방지).
    private var installInProgress: Bool {
        switch phase {
        case .updating, .updated, .failed: return true
        case .idle, .available: return false
        }
    }

    /// 태그 이름 → 판정된 phase(.available 또는 .idle). 순수 — 조회·현재 상태를 건드리지 않는다.
    private func evaluate(_ names: [String]) -> Phase {
        let latest = UpdateCheck.latest(fromTagNames: names)
        if UpdateCheck.isUpdateAvailable(current: current, latest: latest), let latest {
            return .available(latest)
        }
        return .idle
    }

    /// 지금 한 번 확인한다(자동 폴링 루프가 부른다). 조회 실패는 무음 — phase를 건드리지 않는다.
    /// 설치 흐름 중이면 **진입 시·조회 후 모두** 확인해 그 상태를 안 덮는다(사용자 흐름 우선).
    func checkNow() async {
        guard autoCheckEnabled, !isDev, !installInProgress else { return }
        guard let names = await fetchTags() else { return }  // 조회 실패 → 무음, phase 유지
        guard !installInProgress else { return }             // await 뒤 재확인 — 설치가 시작됐으면 안 덮는다
        phase = evaluate(names)
    }

    /// 수동 확인 결과 — 설정 버튼이 사용자에게 피드백으로 보여준다.
    enum ManualResult: Equatable {
        case upToDate           // 최신
        case available(SemVer)  // 새 버전 있음(레일 배지 등장)
        case busy               // 이미 업데이트 진행/완료/실패 중 — 확인 안 함
        case failed             // 조회 실패(오프라인·GitHub 다운 등)
        case devBuild           // 개발 빌드 — 버전이 semver가 아니라 확인이 무의미
    }

    /// 사용자가 설정에서 "지금 확인"을 눌렀다 — **자동확인 off여도** 명시적 요청이라 실행한다.
    /// 업데이트가 있으면 `phase = .available`을 세워 **레일에 배지가 뜨고**, 없으면 이전 배지를 정리한다.
    /// dev 빌드는 버전이 semver가 아니라 확인이 무의미하므로 그 사실을 알린다(오탐·오해 방지).
    func checkManually() async -> ManualResult {
        if isDev { return .devBuild }
        if installInProgress { return .busy }
        guard let names = await fetchTags() else { return .failed }
        if installInProgress { return .busy }                // await 뒤 재확인
        let next = evaluate(names)
        phase = next
        if case .available(let v) = next { return .available(v) }
        return .upToDate
    }

    /// 사용자가 "업데이트"를 눌렀다 — 백그라운드 재빌드를 시작한다(available·failed에서만).
    func startUpdate() async {
        let version: SemVer
        switch phase {
        case .available(let v), .failed(let v, _, _): version = v
        default: return
        }
        guard let root = sourceRoot else {
            phase = .failed(version,
                            message: "소스 저장소를 찾을 수 없습니다 — 터미널에서 재설치하세요:\n"
                                + "curl -fsSL https://raw.githubusercontent.com/yjun1806/muxa/main/scripts/install.sh | bash",
                            logPath: nil)
            return
        }
        phase = .updating(version)
        switch await install(root) {
        case .success:
            phase = .updated(version)
        case .failure(let f):
            phase = .failed(version, message: f.message, logPath: f.logPath)
        }
    }
}

// MARK: - 라이브 조회·설치

extension UpdateChecker {
    /// GitHub 태그 목록(무인증 GET) → 태그 이름 배열. 실패·비200·파싱 실패는 nil(무음).
    nonisolated static let liveFetchTags: @Sendable () async -> [String]? = {
        let url = URL(string: "https://api.github.com/repos/yjun1806/muxa/tags?per_page=20")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return items.compactMap { $0["name"] as? String }
    }

    nonisolated static let liveInstall: @Sendable (String) async -> Result<Void, UpdateInstaller.Failure> = { root in
        do { try await UpdateInstaller.run(sourceRoot: root); return .success(()) }
        catch let f as UpdateInstaller.Failure { return .failure(f) }
        catch { return .failure(.init(message: error.localizedDescription, logPath: nil)) }
    }
}
