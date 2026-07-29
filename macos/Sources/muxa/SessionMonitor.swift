import AppKit
import Foundation
import Observation

/// 세션 관리자 창이 보는 것 — 이 머신의 muxa tmux 세션 전부와 그 무게.
///
/// `ServiceMonitor`와 나란한 위치지만 축이 다르다: 저쪽은 **등록된 서비스**의 상태를 앱 전역에서
/// 상시 관측하고, 이쪽은 **소켓에 실재하는 세션**을 창이 열려 있는 동안만 훑는다. 등록을 기준으로
/// 삼지 않는 것이 핵심이다 — 등록이 사라진 뒤에도 살아남은 세션이 이 창의 대상이다(YJ-6).
///
/// 셸아웃·커널 조회는 전부 주입받는다. 이 계층의 판정(여러 소켓 합치기·고아 표시·무게 잇기·
/// 취소 후 stale write 금지)은 실제 환경 없이 검증돼야 한다.
@Observable
@MainActor
final class SessionMonitor {
    /// 수집된 세션. 정렬은 뷰가 한다(사용자가 컬럼을 고른다).
    private(set) var rows: [TmuxSessionRow] = []
    /// 한 번이라도 훑었는가 — "세션 없음"과 "아직 안 읽음"을 화면에서 갈라야 한다.
    private(set) var hasLoaded = false

    /// 이 앱이 아는 **projectId → 워크스페이스 이름**. 고아 표시와 그룹 이름의 입력으로,
    /// 창을 열 때 `AppState`가 채운다. 비어 있으면 아무것도 고아로 표시되지 않는다
    /// (`TmuxInventory.markOrphans`).
    var knownProjects: [String: String] = [:]

    /// 폴링 주기. 무게가 눈에 띄게 변하는 데 필요한 지연이지 실시간성이 필요한 값이 아니다
    /// (`ServiceMonitor.pollInterval`과 같은 판단·같은 값).
    static let pollInterval: Duration = .seconds(2)

    /// 행의 무게. 모르는 행이면 0 — 표는 빈 칸 대신 0을 보여줘야 "안에 아무것도 없다"가 읽힌다.
    func weight(of row: TmuxSessionRow) -> SessionWeight { weights[row.id] ?? .zero }

    private var weights: [String: SessionWeight] = [:]
    private var previousSnapshot: ProcessSnapshot?
    private var task: Task<Void, Never>?

    /// **세대 카운터** — 취소 뒤 재개한 훑기가 목록을 되살리지 못하게 한다.
    /// 창을 닫는 순간 소켓을 await 중이던 refresh가 그대로 쓰면, 닫힌 창의 폴링이 계속 도는 것처럼
    /// 보인다(`ServiceMonitor.generation`과 같은 이유).
    private var generation = 0

    // MARK: 경계 주입 — 기본값이 실제 tmux·커널, 테스트는 클로저를 갈아 끼운다

    private let listSockets: @MainActor () -> [String]
    private let observeSocket: @MainActor (String) async -> String
    private let takeSnapshot: @MainActor () -> ProcessSnapshot
    private let readProjects: @MainActor (String) -> [String: String]?

    init(sockets: @escaping @MainActor () -> [String] = { TmuxSocketScanner.scan() },
         observe: @escaping @MainActor (String) async -> String = { socket in
             // 서버가 없는 소켓은 exit≠0에 빈 출력이다 — 코드를 보지 않고 출력만 파싱하면
             // 실패·성공을 따로 다룰 필요가 없다(빈 출력 = 빈 결과).
             await TmuxService.run(socket: socket, TmuxInventory.observeArgs,
                                   timeout: TmuxService.observeTimeout).stdout
         },
         snapshot: @escaping @MainActor () -> ProcessSnapshot = { ProcessSampler.snapshot() },
         projects: @escaping @MainActor (String) -> [String: String]? = { folder in
             SessionOwnership.projectWorkspaces(inSupportFolder: folder)
         }) {
        listSockets = sockets
        observeSocket = observe
        takeSnapshot = snapshot
        readProjects = projects
    }

    /// 이 소켓의 세션을 판정할 **등록 목록**(projectId → 워크스페이스). 못 구하면 빈 값 = 판정하지 않는다.
    ///
    /// **소켓마다 주인이 다르다.** 내 인스턴스의 등록으로 남의 소켓 세션을 재면 전부 미등록이 되고,
    /// 표가 온통 "고아"로 물든다(실측에서 41개 중 40개가 그렇게 잘못 표시됐다). 내 소켓은 메모리
    /// 상태를 쓰고 — 파일은 종료 시점 스냅샷이라 낡았다 — 남의 소켓은 그 인스턴스의 지원 폴더를 읽는다.
    private func projects(for socket: String) -> [String: String] {
        if socket == TmuxService.socket { return knownProjects }
        guard let folder = SessionOwnership.supportFolder(for: socket) else { return [:] }
        return readProjects(folder) ?? [:]
    }

    // MARK: 생명주기 — 창이 보일 때만 돈다

    /// 폴링을 시작한다(이미 돌고 있으면 아무것도 하지 않는다).
    func start() {
        guard task == nil, TmuxService.isAvailable else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: SessionMonitor.pollInterval)
            }
        }
    }

    /// 폴링을 멈추고 목록을 비운다.
    ///
    /// 비우는 이유: 다시 열었을 때 **낡은 목록이 잠깐 보이면 사람이 그걸 근거로 죽인다.**
    /// 그 사이 세션이 끝났거나 새로 떴을 수 있고, 무게는 특히 빨리 낡는다.
    func stop() {
        task?.cancel()
        task = nil
        generation &+= 1 // 진행 중이던 훑기의 결과를 버린다
        rows = []
        weights = [:]
        previousSnapshot = nil
        hasLoaded = false
    }

    /// 한 번 훑는다 — 모든 소켓의 세션 + 무게.
    func refresh() async {
        let generation = self.generation

        let sockets = listSockets()
        // **소켓을 동시에 훑는다.** 순차로 돌면 wall-clock이 소켓 수에 비례해 폴링 주기를 잡아먹는다
        // (실측: 16소켓 순차 1390ms / 주기 2000ms). tmux 실행은 백그라운드 큐에서 도므로
        // await 지점마다 MainActor가 풀려 실제로 겹쳐 돈다. 이제 가장 느린 소켓 하나가 상한이다.
        //
        // **응답 없는 소켓도 그대로 둔다** — 빈 출력이 빈 결과가 되므로 따로 거를 필요가 없다.
        // 실측에서 16개 중 10개가 서버 없는 소켓 파일이었고, 하나의 실패로 목록을 비우면 안 된다.
        let outputs = await withTaskGroup(of: (String, String).self) { group in
            for socket in sockets {
                group.addTask { @MainActor in (socket, await self.observeSocket(socket)) }
            }
            var acc: [(socket: String, output: String)] = []
            for await item in group { acc.append(item) }
            return acc
        }
        guard generation == self.generation else { return } // 그 사이 stop이 왔다 — 쓰지 않는다

        var collected: [TmuxSessionRow] = []
        var clientsBySession: [String: [pid_t]] = [:]
        // 소켓 순서를 되돌린다 — TaskGroup의 완료 순서는 비결정적이라 그대로 두면 표의 행이 흔들린다.
        for socket in sockets {
            guard let output = outputs.first(where: { $0.socket == socket })?.output else { continue }
            let parts = TmuxInventory.split(output)
            // 고아 판정은 **소켓별로** 한다(위 knownProjectIds(for:) 주석).
            collected += TmuxInventory.markOrphans(TmuxInventory.parse(parts.panes, socket: socket),
                                                   projectWorkspaces: projects(for: socket))
            clientsBySession.merge(SessionOwnership.parseClients(parts.clients)) { $1 }
        }

        let snapshot = takeSnapshot()
        let ownAppPid = getpid()
        var newWeights: [String: SessionWeight] = [:]
        rows = collected.map { row in
            var row = row
            row.attachment = SessionOwnership.attachment(clientPids: clientsBySession[row.name] ?? [],
                                                         snapshot: snapshot, ownAppPid: ownAppPid)
            newWeights[row.id] = ProcessSampler.weight(of: row.panePid,
                                                       current: snapshot, previous: previousSnapshot)
            return row
        }
        weights = newWeights
        previousSnapshot = snapshot
        hasLoaded = true
    }
}
