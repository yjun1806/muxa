import Bonsplit
import Foundation
import Testing
@testable import muxa

/// IDE 서버 장부의 불변식 — **하나의 셸(tmux 세션)엔 서버 하나**. reattach가 같은 세션에 새 탭을
/// 만들어 붙이므로, 탭 기준으로 판단하면 같은 셸에 서버가 둘 생긴다(YJ-3 리뷰 I-1).
struct IdeSessionLedgerTests {
    private let session = "muxa__F2AF1DD9__term__4E78113E"
    private let other = "muxa__F2AF1DD9__term__B5B67391"

    // MARK: 세션 기준 식별

    @Test func 다른_탭이라도_같은_세션이면_같은_기록이다() {
        // reattach: 백그라운드 세션을 되찾을 때 새 TabID가 기존 세션 이름을 물려받는다.
        var ledger = IdeSessionLedger()
        let old = TabID(), new = TabID()
        ledger.attach(tab: old, to: session)
        ledger.attach(tab: new, to: session)
        #expect(Set(ledger.tabs(of: session)) == Set([old, new]))
    }

    @Test func 다른_세션은_섞이지_않는다() {
        var ledger = IdeSessionLedger()
        let a = TabID(), b = TabID()
        ledger.attach(tab: a, to: session)
        ledger.attach(tab: b, to: other)
        #expect(ledger.tabs(of: session) == [a])
        #expect(ledger.tabs(of: other) == [b])
    }

    // MARK: 탭이 닫힐 때 vs 세션이 죽을 때

    @Test func 탭이_닫히면_기록만_지우고_포트_기억은_남는다() {
        // 백그라운드 keep — 세션과 claude는 살아 있다. 포트를 잊으면 되찾을 수 없다.
        var ledger = IdeSessionLedger()
        let tab = TabID()
        ledger.attach(tab: tab, to: session)
        _ = ledger.remember(port: 63481, for: session)

        ledger.detach(tab: tab)
        #expect(ledger.tabs(of: session).isEmpty) // 닫힌 탭은 라우팅 후보가 아니다
        #expect(ledger.ports[session] == 63481)   // 기억은 남는다
    }

    @Test func 닫힌_탭_자리에_새_탭이_같은_세션을_물려받는다() {
        // reattach 경로 — 서버·포트를 그대로 이어써야 claude가 붙어 있는 채로 다시 이어진다.
        var ledger = IdeSessionLedger()
        let old = TabID(), new = TabID()
        ledger.attach(tab: old, to: session)
        _ = ledger.remember(port: 63481, for: session)
        ledger.detach(tab: old)

        ledger.attach(tab: new, to: session)
        #expect(ledger.tabs(of: session) == [new])
        #expect(ledger.ports[session] == 63481)
    }

    // MARK: 포트 기억

    @Test func 바뀐_포트만_저장이_필요하다() {
        var ledger = IdeSessionLedger()
        #expect(ledger.remember(port: 63481, for: session) == true)
        #expect(ledger.remember(port: 63481, for: session) == false) // 같은 값 → 저장 생략
        #expect(ledger.remember(port: 63482, for: session) == true)
        #expect(ledger.ports[session] == 63482)
    }

    // MARK: 세션이 죽었을 때

    @Test func 세션이_죽으면_그_세션의_탭_기록과_포트를_모두_지운다() {
        var ledger = IdeSessionLedger()
        let old = TabID(), new = TabID(), unrelated = TabID()
        ledger.attach(tab: old, to: session)
        ledger.attach(tab: new, to: session)
        ledger.attach(tab: unrelated, to: other)
        _ = ledger.remember(port: 63481, for: session)
        _ = ledger.remember(port: 63490, for: other)

        #expect(ledger.sessionDied(tab: new) == session)
        // detach로 남은 옛 탭 기록까지 함께 사라져야 한다 — 찌꺼기가 남으면 다음 판정이 어긋난다.
        #expect(ledger.tabs(of: session).isEmpty)
        #expect(ledger.ports[session] == nil)
        // 남의 세션은 그대로다.
        #expect(ledger.tabs(of: other) == [unrelated])
        #expect(ledger.ports[other] == 63490)
    }

    @Test func 모르는_탭의_죽음은_아무것도_안_바꾼다() {
        var ledger = IdeSessionLedger(ports: [session: 63481])
        let before = ledger
        #expect(ledger.sessionDied(tab: TabID()) == nil)
        #expect(ledger == before)
    }
}
