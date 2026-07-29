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

    /// 아는 프로젝트 id. 고아 표시의 입력으로, 창을 열 때 `AppState`가 채운다.
    /// 비어 있으면 아무것도 고아로 표시되지 않는다(`TmuxInventory.markOrphans`).
    var knownProjectIds: Set<String> = []

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
    private let readPanes: @MainActor (String) async -> String?
    private let takeSnapshot: @MainActor () -> ProcessSnapshot

    init(sockets: @escaping @MainActor () -> [String] = { TmuxSocketScanner.scan() },
         panes: @escaping @MainActor (String) async -> String? = { socket in
             let out = await TmuxService.run(socket: socket,
                                             ["list-panes", "-a", "-F", TmuxInventory.paneFormat],
                                             timeout: TmuxService.observeTimeout)
             return out.exitCode == 0 ? out.stdout : nil
         },
         snapshot: @escaping @MainActor () -> ProcessSnapshot = { ProcessSampler.snapshot() }) {
        listSockets = sockets
        readPanes = panes
        takeSnapshot = snapshot
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

        var collected: [TmuxSessionRow] = []
        for socket in listSockets() {
            // **응답 없는 소켓은 건너뛰고 나머지는 보여준다.** 실측에서 16개 중 10개가 서버 없는
            // 소켓 파일이었다 — 하나의 실패로 목록을 비우면 창이 통째로 쓸모없어진다.
            guard let stdout = await readPanes(socket) else { continue }
            collected += TmuxInventory.parse(stdout, socket: socket)
        }
        guard generation == self.generation else { return } // 그 사이 stop이 왔다 — 쓰지 않는다

        let snapshot = takeSnapshot()
        let marked = TmuxInventory.markOrphans(collected, knownProjectIds: knownProjectIds)
        weights = marked.reduce(into: [:]) { acc, row in
            acc[row.id] = ProcessSampler.weight(of: row.panePid,
                                                current: snapshot, previous: previousSnapshot)
        }
        rows = marked
        previousSnapshot = snapshot
        hasLoaded = true
    }
}
