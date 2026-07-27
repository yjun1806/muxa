import Bonsplit
import Foundation

/// IDE 서버의 **장부**(순수) — 어느 탭이 어느 tmux 세션에 속하고, 그 세션이 어떤 포트를 쓰던지.
/// 서버 객체·소켓은 `IdeServerRegistry`가 들고, 여기는 기록과 판정만 한다(테스트로 못 박는다).
///
/// **하나의 셸엔 서버 하나**가 이 장부의 핵심 불변식이다. `TerminalStore.reattach`는 백그라운드
/// 세션을 되찾을 때 **새 TabID를 만들어 기존 세션 이름을 물려주므로**(`reattach`), 탭 id를 기준으로
/// 서버를 재사용하면 같은 셸에 서버가 둘 생긴다 — claude는 env에 박힌 옛 포트에 붙어 있는데 선택은
/// 새 서버로 흘러 서로 어긋나고, 포트 기억까지 새 번호로 덮인다(YJ-3 리뷰 I-1).
/// 그래서 **세션 이름을 기준**으로 잡는다.
struct IdeSessionLedger: Equatable {
    /// 탭 → 그 탭이 붙어 있는 tmux 세션. 여러 탭이 같은 세션을 가리킬 수 있다(reattach).
    private(set) var sessionOf: [TabID: String] = [:]
    /// 세션 → 지난 실행에서 쓰던 포트.
    private(set) var ports: [String: UInt16] = [:]

    init(ports: [String: UInt16] = [:]) {
        self.ports = ports
    }

    /// 이 탭이 이 세션에 붙었다고 기록한다.
    mutating func attach(tab: TabID, to session: String) {
        sessionOf[tab] = session
    }

    /// 이 세션이 실제로 잡은 포트를 기록한다. **바뀐 게 없으면 false** — 호출부가 불필요한 저장을 건너뛴다.
    mutating func remember(port: UInt16, for session: String) -> Bool {
        guard ports[session] != port else { return false }
        ports[session] = port
        return true
    }

    /// 탭이 닫혔다(세션은 백그라운드로 살 수 있다) — **탭 기록만** 지운다. 서버도 포트 기억도 남긴다.
    /// 이걸 안 하면 닫힌 탭이 계속 그 셸을 가리켜, 라우팅 대상이 "하나"인지 세는 판정이 어긋난다.
    mutating func detach(tab: TabID) {
        sessionOf[tab] = nil
    }

    /// 이 탭의 tmux 세션이 죽었다 — 그 세션을 가리키던 **모든 탭 기록과 포트 기억**을 지우고
    /// 죽은 세션 이름을 돌려준다(호출부가 그 서버를 내린다). 모르는 탭이면 nil.
    ///
    /// 세션을 가리키던 탭을 전부 지우는 이유: 백그라운드로 놓아둔 탭(detach)은 닫혀도 여기서
    /// 지워지지 않아 기록이 남는데, 그 찌꺼기를 남기면 다음 판정이 어긋난다.
    mutating func sessionDied(tab: TabID) -> String? {
        guard let session = sessionOf[tab] else { return nil }
        sessionOf = sessionOf.filter { $0.value != session }
        ports[session] = nil
        return session
    }

    /// 지금 이 세션을 가리키는 탭들 — 라우팅 대상 판정에 쓴다.
    func tabs(of session: String) -> [TabID] {
        sessionOf.compactMap { $0.value == session ? $0.key : nil }
    }
}
