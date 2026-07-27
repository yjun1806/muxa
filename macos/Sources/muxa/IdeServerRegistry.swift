import Foundation
import Bonsplit

/// **CC 칸마다 독립 IDE 서버**를 소유한다 — 각 claude 세션이 자기 포트/락파일에 붙어, 문서 선택이
/// **그 세션에만** 라우팅된다(VS Code가 창마다 엔드포인트를 갖는 것과 같은 진짜 격리). 부작용(서버 수명·
/// 락파일)을 이 경계에 모은다. AppState가 소유하고, TerminalStore가 `env(for:)`로 탭별 포트를 주입받는다.
///
/// **서버는 tmux 세션(=셸) 단위다**, 탭 단위가 아니다. `reattach`가 백그라운드 세션을 되찾을 때
/// 새 TabID로 같은 세션에 붙으므로, 탭 기준이면 같은 셸에 서버가 둘 생겨 claude(옛 포트에 붙어 있다)와
/// 선택 라우팅이 어긋난다. 탭↔세션↔포트 장부는 순수 타입 `IdeSessionLedger`가 갖는다(테스트로 못 박음).
@MainActor
final class IdeServerRegistry {
    /// tmux 세션 이름 → 그 셸의 서버. **셸 하나에 서버 하나.**
    private var servers: [String: IdeServer] = [:]
    /// 탭↔세션↔포트 기록(순수). 서버 객체만 여기 밖에 있다.
    private var ledger: IdeSessionLedger
    private let version: String
    private let ideName: String
    /// 새 서버가 락파일에 실을 워크스페이스 루트 — 열릴 때마다 최신값을 읽는다(AppState가 채운다).
    var workspaceFolders: () -> [String] = { [] }

    init(version: String, ideName: String) {
        self.version = version
        self.ideName = ideName
        self.ledger = IdeSessionLedger(ports: IdePortStore.load())
        IdeLockfile.cleanOrphans(ideName: ideName) // 앱 시작 시 1회: 이전 실행이 남긴 죽은 락파일 정리(우리 것만)
    }

    /// 이 탭이 붙은 셸의 서버를 (없으면 만들어) 반환. 터미널 생성 시 env로 포트를 심어야 하므로
    /// start가 포트를 동기 확보한다. `session`은 그 탭의 tmux 세션 이름 — 서버와 포트 기억의 키다.
    @discardableResult
    func server(for tabId: TabID, session: String) -> IdeServer {
        ledger.attach(tab: tabId, to: session)
        if let s = servers[session] { return s } // 같은 셸이면 서버를 새로 만들지 않는다
        let s = IdeServer(version: version, ideName: ideName)
        s.start(workspaceFolders: workspaceFolders(),
                preferredPort: IdePortStore.preferredPort(ledger.ports, for: session))
        servers[session] = s
        // 실제로 잡은 번호를 기억한다 — 원하던 포트를 못 얻어 물러섰다면 그 새 번호가 기준이 된다.
        if let port = s.port, ledger.remember(port: port, for: session) {
            IdePortStore.save(ledger.ports)
        }
        return s
    }

    /// 이 탭 터미널에 심을 IDE env(그 셸의 서버 포트). 터미널 생성부에서 호출.
    func env(for tabId: TabID, session: String) -> [String: String] {
        server(for: tabId, session: session).terminalEnv
    }

    /// 이 탭에 claude가 붙어 있나 — 라우팅 대상(마지막 활성 CC) 판정.
    func isConnected(_ tabId: TabID) -> Bool { server(of: tabId)?.isConnected ?? false }

    /// 지금 claude가 붙어 있는 CC 탭들 — 라우팅 대상 선택(하나면 항상 그 하나, 여럿이면 포커스 기준).
    func connectedTabs() -> [TabID] {
        servers.filter { $0.value.isConnected }.flatMap { ledger.tabs(of: $0.key) }
    }

    /// 선택을 **이 탭이 붙은 셸의 서버로만** 흘린다(격리). 서버 없으면 무동작.
    func route(_ selection: IdeSelection, to tabId: TabID) {
        server(of: tabId)?.updateContext { $0.selection = selection }
    }

    /// 이 탭의 공유 컨텍스트를 지운다(푸터 ✕).
    func clear(_ tabId: TabID) { server(of: tabId)?.clearSelection() }

    /// 탭이 닫혔다(`onCloseTab`) — 그 탭이 이 셸을 가리키던 **기록만** 지운다. 서버는 유지한다
    /// (백그라운드 keep 시 세션·claude가 산다). 가리키는 탭이 없어지면 라우팅 대상에서 자연히 빠지고,
    /// 나중에 `reattach`로 새 탭이 붙으면 같은 서버를 그대로 물려받는다.
    func detach(_ tabId: TabID) { ledger.detach(tab: tabId) }

    /// 이 탭의 **tmux 세션이 죽었다**(`onSessionKilled`) — 그 셸의 서버를 내리고 락파일을 지우며,
    /// 포트 기억도 버린다. 세션이 살아 있는 한(백그라운드 keep) 여기 오지 않으므로 기억이 유지된다.
    func remove(_ tabId: TabID) {
        guard let session = ledger.sessionDied(tab: tabId) else { return }
        servers[session]?.stop()
        servers[session] = nil
        IdePortStore.save(ledger.ports)
    }

    /// 앱 종료 — 모든 서버를 내려 락파일을 정리한다. **포트 기억은 남긴다** — 다음 실행에서 같은
    /// 세션이 같은 번호로 돌아오는 게 이 기억의 존재 이유다.
    func stopAll() {
        servers.values.forEach { $0.stop() }
        servers.removeAll()
    }

    /// 이 탭이 붙은 셸의 서버(없으면 nil).
    private func server(of tabId: TabID) -> IdeServer? {
        ledger.sessionOf[tabId].flatMap { servers[$0] }
    }
}
