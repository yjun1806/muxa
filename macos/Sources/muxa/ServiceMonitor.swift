import AppKit
import Foundation
import Observation

/// 서비스 상태 관측 — **접혀 있어도(서피스 렌더 없이) 돈다.** 진실 원천은 tmux다.
///
/// 폴링이 하나뿐인 이유: `list-panes -a`가 모든 세션의 상태를 한 번에 준다. 프로젝트마다 스토어를
/// 두면 같은 명령을 N번 돌리게 되므로, 앱 전체에 모니터 하나를 두고 서비스 id로 색인한다.
///
/// tmux 셸아웃은 **주입 가능**하다(`readStates`·`readLog`·`now`). 이 타입의 판정(죽음 전이 1회 발화·
/// 취소 후 stale write 금지·포트 백오프)은 tmux 없이 결정론적으로 검증돼야 한다 — 알림의 유일한
/// 결정론적 신호가 여기서 나온다.
@Observable
@MainActor
final class ServiceMonitor {
    /// serviceId → 상태. 등록됐지만 tmux에 없으면 키가 없다(= .missing).
    private(set) var states: [String: ServiceState] = [:]
    /// serviceId → 리슨 포트. 한 번 찾으면 캐시한다(매번 capture-pane 하지 않게).
    private(set) var ports: [String: Int] = [:]

    /// 뷰가 쓰는 조회 — "키 없음 = .missing" 매핑이 도크·팝오버·칩에 세 번 복붙돼 있었다.
    func state(of serviceId: String) -> ServiceState { states[serviceId] ?? .missing }

    /// 서비스가 죽었을 때 부른다(running → exited 전이 순간 1회). 알림·배지 배선은 AppState가 소유.
    var onExit: ((Service, Int32) -> Void)?

    /// 폴링 주기. 로그를 스트리밍하는 게 아니라 상태 점을 갱신하는 용도라 2초면 충분하다
    /// (사람이 "죽었네"를 알아채는 데 필요한 지연이지, 실시간성이 필요한 값이 아니다).
    static let pollInterval: Duration = .seconds(2)
    /// 앱이 비활성일 때의 주기. 아무도 안 보는 화면을 위해 2초마다 프로세스를 띄우면 App Nap이
    /// 걸리지 않아 배터리를 계속 먹는다. 돌아오는 순간 즉시 한 번 훑으므로(activate) 지연은 안 보인다.
    static let idlePollInterval: Duration = .seconds(30)

    /// 포트 조회 백오프 — 콜드 컴파일로 포트를 늦게 찍는 서버가 흔해서 "N회 후 포기"는 못 쓴다
    /// (2초 폴링이면 10초 만에 포기해 포트를 영영 못 잡는다). 대신 간격을 늘려 오래 기다린다:
    /// 2 → 4 → 8 … → 60초 상한. 포트를 안 쓰는 서비스(워커·`--watch`)도 결국 분당 1회로 잦아든다.
    static let portProbeInitialDelay: TimeInterval = 2
    static let portProbeMaxDelay: TimeInterval = 60

    /// 포트를 아직 못 찾은 서비스의 다음 조회 시각과 그때 쓸 간격.
    private struct PortProbe {
        var delay: TimeInterval
        var dueAt: Date
    }
    private var probes: [String: PortProbe] = [:]

    // MARK: 경계 주입 — 기본값이 실제 tmux, 테스트는 클로저를 갈아 끼운다

    private let readStates: () async -> [String: ServiceState]
    private let readLog: (_ projectId: String, _ serviceId: String) async -> String
    private let now: () -> Date

    /// 포트를 찾을 때 읽는 스크롤백 줄 수 — 기동 배너가 이 안에 있어야 한다.
    static let portCaptureLines = 60

    init(states: @escaping () async -> [String: ServiceState] = { await TmuxService.states() },
         capture: @escaping (String, String) async -> String = {
             await TmuxService.capture(projectId: $0, serviceId: $1, lines: ServiceMonitor.portCaptureLines)
         },
         now: @escaping () -> Date = Date.init,
         observeAppActivity: Bool = true) {
        self.readStates = states
        self.readLog = capture
        self.now = now
        guard observeAppActivity else { return }
        observe(NSApplication.didResignActiveNotification) { $0.setActive(false) }
        observe(NSApplication.didBecomeActiveNotification) { $0.setActive(true) }
    }

    private func observe(_ name: Notification.Name, _ action: @escaping (ServiceMonitor) -> Void) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
    }

    private var isActive = true
    private var pollInterval: Duration { isActive ? Self.pollInterval : Self.idlePollInterval }

    /// 활성 전환 시 폴링을 다시 건다 — 잠들어 있던 30초 sleep을 기다리지 않고 즉시 한 번 훑는다.
    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        guard task != nil else { return } // 폴링 중일 때만(서비스 0개면 아무것도 안 한다)
        sync(services: tracked)
    }

    private var task: Task<Void, Never>?
    private var tracked: [Service] = []

    /// **세대 카운터** — in-flight refresh의 stale write를 막는다.
    ///
    /// 마지막 서비스를 지우면 sync가 states를 비우고 폴링을 멈추는데, 그 순간 `readStates()`를 await
    /// 중이던 refresh가 재개해 아직 살아 있는 세션을 보고 삭제된 id를 `.running`으로 되살린다.
    /// 폴링이 멈춰 그걸 지울 사람이 없으므로 **삭제한 서비스의 칩이 영구히 남는다.**
    /// sync가 세대를 올리고, refresh는 시작 시 캡처해 **대입 직전마다** 비교한다(await 뒤마다).
    private var generation = 0

    /// 기동 후 첫 refresh를 지났는가 — 첫 훑기는 baseline이라 앱 시작 전에 **이미 죽어 있던** 세션을
    /// 재알림하지 않는다. 이후의 죽음만 알린다(아래 onExit 게이트). sync가 다시 불려도 리셋하지 않는다
    /// (서비스를 새로 추가한 직후 그게 즉사하면 baseline이 아니라 진짜 죽음으로 잡혀야 하므로).
    private var hasBaselined = false

    /// 등록된 서비스 전체(모든 워크스페이스)를 넘겨 폴링을 시작·갱신한다.
    /// 서비스가 하나도 없으면 폴링을 멈춘다 — 아무도 안 쓰는 기능이 2초마다 프로세스를 띄우지 않게.
    func sync(services: [Service]) {
        task?.cancel()
        generation &+= 1
        tracked = services
        guard TmuxService.isAvailable, !services.isEmpty else {
            task = nil
            states = [:]
            ports = [:]
            probes = [:]
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(services: services)
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        generation &+= 1 // 진행 중이던 refresh의 결과를 버린다(취소 후 stale write 금지)
    }

    /// 한 번 훑는다 — 상태 갱신 + 죽음 전이 감지 + (아직 모르는) 포트 조회.
    func refresh(services: [Service]) async {
        let generation = self.generation
        let byId = Self.index(services)
        let bySession = await readStates()
        guard generation == self.generation else { return } // 그 사이 sync/stop이 왔다 — 쓰지 않는다

        // 세션명 키 → 서비스 id 키로 옮긴다. muxa 소유가 아닌 세션은 parse가 걸러낸다.
        // 이때 projectId도 함께 챙긴다 — 나중에 세션 목록을 다시 훑어(O(N·M)) 되찾을 이유가 없다.
        var next: [String: ServiceState] = [:]
        var projectOf: [String: String] = [:]
        for (session, state) in bySession {
            guard let parsed = ServiceSession.parse(session), byId[parsed.serviceId] != nil else { continue }
            next[parsed.serviceId] = state
            projectOf[parsed.serviceId] = parsed.projectId
        }

        // 죽음 전이를 1회만 알린다. running→exited뿐 아니라 **첫 폴링 전에 즉사한** missing→exited도 잡는다
        // — dev 서버가 오타·포트선점으로 1초 안에 죽는 게 가장 흔한 실패인데 종전엔 이게 침묵했다.
        // 이미 exited였던 걸 매 폴링마다 다시 알리지 않도록 "직전이 exited가 아닐 때"만 발화하고,
        // baseline(첫 훑기) 전에 이미 죽어 있던 세션은 hasBaselined 게이트로 제외한다.
        for (id, state) in next {
            guard case .exited(let code) = state, let service = byId[id] else { continue }
            let wasExited: Bool = { if case .exited = states[id] { return true }; return false }()
            if hasBaselined && !wasExited { onExit?(service, code) }
        }

        // **재시작하면 포트 캐시를 버린다.** 캐시는 재시작을 살아남는데 새 프로세스는 다른 포트를 잡을 수
        // 있다(3000이 아직 물려 있으면 3001). 옛 포트를 그대로 띄우면 칩이 거짓말을 하고, 그 순간
        // 이 기능의 유일한 상시 신호가 신뢰를 잃는다. 조회 예산(백오프)도 함께 리셋한다.
        for (id, state) in next where state == .running && states[id] != .running {
            ports[id] = nil
            probes[id] = nil
        }

        states = next
        hasBaselined = true
        ports = ports.filter { next[$0.key] != nil } // 등록이 사라진 서비스의 포트 캐시 정리
        probes = probes.filter { next[$0.key] != nil }

        // 포트는 아직 모르는 running 서비스만, 그것도 백오프가 허락하는 시각에만 조회한다.
        for (id, state) in next where state == .running && ports[id] == nil {
            let probe = probes[id] ?? PortProbe(delay: Self.portProbeInitialDelay, dueAt: now())
            probes[id] = probe
            guard now() >= probe.dueAt, let projectId = projectOf[id] else { continue }
            let log = await readLog(projectId, id)
            guard generation == self.generation else { return }
            if let port = ServiceSession.extractPort(log) {
                ports[id] = port
                probes[id] = nil
            } else {
                probes[id] = PortProbe(delay: min(probe.delay * 2, Self.portProbeMaxDelay),
                                       dueAt: now().addingTimeInterval(probe.delay))
            }
        }
    }

    /// serviceId → 서비스 색인(순수).
    ///
    /// **`Dictionary(uniqueKeysWithValues:)`를 쓰면 안 된다** — 중복 키에서 fatalError다. 저장 파일이
    /// 손상돼(프로젝트 블록 복붙·동기화 충돌) 같은 serviceId가 둘 생기면 첫 폴링(2초)에서 앱이 죽고,
    /// 다시 켜도 같은 파일을 읽어 또 죽는다 = 영구 부팅 불가. 저장 파일은 신뢰 경계 밖이다
    /// (SnapshotSanitize와 같은 원칙 — 변조된 입력에 죽지 않는다). 중복은 **먼저 온 것을 남긴다**.
    static func index(_ services: [Service]) -> [String: Service] {
        Dictionary(services.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
