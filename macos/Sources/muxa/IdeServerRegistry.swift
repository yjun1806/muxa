import Foundation
import Bonsplit

/// **CC 칸마다 독립 IDE 서버**를 소유한다 — 각 claude 세션이 자기 포트/락파일에 붙어, 문서 선택이
/// **그 세션에만** 라우팅된다(VS Code가 창마다 엔드포인트를 갖는 것과 같은 진짜 격리). 부작용(서버 수명·
/// 락파일)을 이 경계에 모은다. AppState가 소유하고, TerminalStore가 `env(for:)`로 탭별 포트를 주입받는다.
@MainActor
final class IdeServerRegistry {
    private var servers: [TabID: IdeServer] = [:]
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
    @discardableResult
    func server(for tabId: TabID) -> IdeServer {
        if let s = servers[tabId] { return s }
        let s = IdeServer(version: version, ideName: ideName)
        s.start(workspaceFolders: workspaceFolders())
        servers[tabId] = s
        return s
    }

    /// 이 탭 터미널에 심을 IDE env(자기 서버 포트). 터미널 생성부에서 호출.
    func env(for tabId: TabID) -> [String: String] { server(for: tabId).terminalEnv }

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

    /// 탭이 닫혔다 — 서버를 내리고 락파일을 지운다.
    func remove(_ tabId: TabID) {
        servers[tabId]?.stop()
        servers[tabId] = nil
    }

    /// 앱 종료 — 모든 서버를 내려 락파일을 정리한다.
    func stopAll() {
        servers.values.forEach { $0.stop() }
        servers.removeAll()
    }
}
