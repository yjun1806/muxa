import Foundation
import Bonsplit

/// **CC 칸마다 독립 IDE 서버**를 소유한다 — 각 claude 세션이 자기 포트/락파일에 붙어, 문서 선택이
/// **그 세션에만** 라우팅된다(VS Code가 창마다 엔드포인트를 갖는 것과 같은 진짜 격리). 부작용(서버 수명·
/// 락파일)을 이 경계에 모은다. AppState가 소유하고, TerminalStore가 `env(for:)`로 탭별 포트를 주입받는다.
@MainActor
final class IdeServerRegistry {
    private var servers: [TabID: IdeServer] = [:]
    /// 탭 → 그 탭의 tmux 세션 이름. 포트 기억의 키다 — **탭 id는 재시작 때 새로 생기지만**
    /// 세션 이름은 저장돼 살아남는다(이유는 `IdePortStore`). 탭이 닫힐 때 기억을 지우는 데 쓴다.
    private var sessionOf: [TabID: String] = [:]
    /// 세션이 지난 실행에서 쓰던 포트 — 같은 번호로 돌아가야 그 셸의 claude가 다시 붙는다.
    /// 메모리 사본을 들고 바뀔 때만 파일에 쓴다.
    private var rememberedPorts: [String: UInt16] = IdePortStore.load()
    private let version: String
    private let ideName: String
    /// 새 서버가 락파일에 실을 워크스페이스 루트 — 열릴 때마다 최신값을 읽는다(AppState가 채운다).
    var workspaceFolders: () -> [String] = { [] }

    init(version: String, ideName: String) {
        self.version = version
        self.ideName = ideName
        IdeLockfile.cleanOrphans(ideName: ideName) // 앱 시작 시 1회: 이전 실행이 남긴 죽은 락파일 정리(우리 것만)
    }

    /// 이 탭의 서버를 (없으면 만들어) 반환. 터미널 생성 시 env로 포트를 심어야 하므로 start가 포트를 동기 확보한다.
    /// `session`은 그 탭의 tmux 세션 이름 — 포트 기억의 키다.
    @discardableResult
    func server(for tabId: TabID, session: String) -> IdeServer {
        if let s = servers[tabId] { return s }
        let s = IdeServer(version: version, ideName: ideName)
        s.start(workspaceFolders: workspaceFolders(),
                preferredPort: IdePortStore.preferredPort(rememberedPorts, for: session))
        servers[tabId] = s
        sessionOf[tabId] = session
        // 실제로 잡은 번호를 기억한다 — 원하던 포트를 못 얻어 물러섰다면 그 새 번호가 기준이 된다.
        if let port = s.port, rememberedPorts[session] != port {
            rememberedPorts[session] = port
            IdePortStore.save(rememberedPorts)
        }
        return s
    }

    /// 이 탭 터미널에 심을 IDE env(자기 서버 포트). 터미널 생성부에서 호출.
    func env(for tabId: TabID, session: String) -> [String: String] {
        server(for: tabId, session: session).terminalEnv
    }

    /// 이 탭에 claude가 붙어 있나 — 라우팅 대상(마지막 활성 CC) 판정.
    func isConnected(_ tabId: TabID) -> Bool { servers[tabId]?.isConnected ?? false }

    /// 지금 claude가 붙어 있는 CC 탭들 — 라우팅 대상 선택(하나면 항상 그 하나, 여럿이면 포커스 기준).
    func connectedTabs() -> [TabID] { servers.compactMap { $0.value.isConnected ? $0.key : nil } }

    /// 선택을 **이 탭의 서버로만** 흘린다(격리). 서버 없으면 무동작.
    func route(_ selection: IdeSelection, to tabId: TabID) {
        servers[tabId]?.updateContext { $0.selection = selection }
    }

    /// 이 탭의 공유 컨텍스트를 지운다(푸터 ✕).
    func clear(_ tabId: TabID) { servers[tabId]?.clearSelection() }

    /// 탭이 닫혔다 — 서버를 내리고 락파일을 지운다. 기억해 둔 포트도 함께 버린다(세션 이름은
    /// 재사용되지 않으므로, 안 지우면 죽은 세션 항목이 영영 쌓인다).
    func remove(_ tabId: TabID) {
        servers[tabId]?.stop()
        servers[tabId] = nil
        if let session = sessionOf.removeValue(forKey: tabId),
           rememberedPorts.removeValue(forKey: session) != nil {
            IdePortStore.save(rememberedPorts)
        }
    }

    /// 앱 종료 — 모든 서버를 내려 락파일을 정리한다. **포트 기억은 남긴다** — 다음 실행에서 같은
    /// 세션이 같은 번호로 돌아오는 게 이 기억의 존재 이유다.
    func stopAll() {
        servers.values.forEach { $0.stop() }
        servers.removeAll()
        sessionOf.removeAll()
    }
}
