import Foundation
import Testing
@testable import muxa

/// 종료 전 경고의 판정(순수) — **이 창에서 유일하게 파괴적인 동작**의 마지막 방어선.
///
/// 자동 GC는 `knownProjectIds` 가드로 안전을 샀지만(그래서 고아를 못 지운다), 이 창은 그 판정을
/// 사람에게 넘긴다. 넘기는 대신 **무엇을 죽이는지 먼저 말해줘야** 한다.
struct SessionKillPlanTests {
    private let mine = "muxa-services"

    private func item(socket: String = "muxa-services", dead: Bool = false, attached: Bool = false,
                      processes: Int = 2, labels: [String] = [],
                      orphan: Bool = false) -> SessionListItem {
        var row = TmuxSessionRow(socket: socket, name: "muxa__P__term__T", kind: .terminal, projectId: "P",
                                 isDead: dead, isAttached: attached, createdAt: nil, path: "/x", panePid: 1)
        row.isOrphan = orphan
        row.attachment = attached ? .otherApp(name: "muxa", pid: 1) : .detached
        return SessionListItem(row: row, weight: SessionWeight(cpuPercent: 0, footprintBytes: 0,
                                                               processCount: processes, labels: labels))
    }

    /// 내 소켓의 **빈 셸**은 묻지 않는다 — 되찾을 것이 없는 걸 죽일 때마다 확인창이 뜨면
    /// 사람이 확인창을 읽지 않고 누르는 습관이 든다(정작 위험할 때 못 막는다).
    @Test func emptyShellOnOwnSocketNeedsNoConfirmation() {
        #expect(SessionKillPlan.warning(for: [item()], ownSocket: mine) == nil)
    }

    /// 죽은 pane도 묻지 않는다 — 안에 프로세스가 없다.
    @Test func deadPaneNeedsNoConfirmation() {
        #expect(SessionKillPlan.warning(for: [item(dead: true, processes: 0)], ownSocket: mine) == nil)
    }

    /// **안에서 뭔가 돌고 있으면 반드시 묻는다.** 실측의 986MB짜리 스크립트 세션이 이 경우다 —
    /// 고아로 분류됐지만 헤드리스 크롬과 esbuild가 돌고 있었다.
    @Test func runningWorkWarnsWithNames() throws {
        let warning = try #require(SessionKillPlan.warning(
            for: [item(processes: 19, labels: ["esbuild", "node"])], ownSocket: mine))
        #expect(warning.detail.contains("esbuild"))
    }

    /// 다른 소켓의 세션은 **다른 muxa 인스턴스가 쓰는 중일 수 있다**. D19의 격리가 지키려던 바로 그 선이라,
    /// 읽기는 넘어가도 죽이기는 여기서 한 번 멈춘다.
    @Test func foreignSocketWarns() throws {
        let warning = try #require(SessionKillPlan.warning(for: [item(socket: "muxa-services-dev-1")],
                                                          ownSocket: mine))
        #expect(warning.detail.contains("다른"))
    }

    /// 연결된 세션을 죽이면 보고 있던 화면이 사라진다.
    @Test func attachedSessionWarns() {
        #expect(SessionKillPlan.warning(for: [item(attached: true)], ownSocket: mine) != nil)
    }

    /// 여럿을 고르면 **하나라도 위험하면** 묻는다 — 안전한 것에 섞여 위험한 게 조용히 지나가면 안 된다.
    @Test func anyRiskyItemTriggersConfirmation() {
        let items = [item(), item(), item(processes: 19, labels: ["pnpm"])]
        #expect(SessionKillPlan.warning(for: items, ownSocket: mine) != nil)
    }

    /// 제목은 몇 개를 죽이는지 말한다.
    @Test func titleStatesCount() throws {
        let warning = try #require(SessionKillPlan.warning(for: [item(attached: true), item(attached: true)],
                                                          ownSocket: mine))
        #expect(warning.title.contains("2"))
    }

    /// 고를 게 없으면 경고도 없다(버튼이 비활성이어야 하지만, 판정도 방어한다).
    @Test func emptySelectionHasNoWarning() {
        #expect(SessionKillPlan.warning(for: [], ownSocket: mine) == nil)
    }

    /// 죽고·비었고·등록 없는 것만 골라낸다.
    @Test func sweepSelectsDeadOrphansOnly() {
        let items = [item(dead: true, processes: 0, orphan: true),
                     item(),
                     item(dead: true, processes: 0, orphan: true)]
        let swept = SessionKillPlan.sweepable(items)
        let allDead = swept.allSatisfy { $0.row.isDead } // rethrows라 매크로 밖에서 계산한다
        #expect(swept.count == 2)
        #expect(allDead)
    }

    /// **죽은 pane이라도 안에 프로세스가 남아 있으면 뺀다.**
    /// tmux는 pane을 죽은 것으로 표시해도 자식이 살아남는 경우가 있다(고아 프로세스).
    @Test func sweepSkipsDeadWithLiveProcesses() {
        #expect(SessionKillPlan.sweepable([item(dead: true, processes: 3, orphan: true)]).isEmpty)
    }

    /// **등록이 살아 있는 스크립트의 종료 pane은 쓸지 않는다.**
    /// muxa는 그 pane을 일부러 남긴다 — exit code와 마지막 로그를 읽는 유일한 경로다
    /// (`ScriptSession.orphans`가 같은 이유로 같은 것을 보존한다). 쓸어버리면 "왜 실패했는지"를
    /// 영영 못 본다.
    @Test func sweepKeepsRegisteredScriptLogs() {
        #expect(SessionKillPlan.sweepable([item(dead: true, processes: 0, orphan: false)]).isEmpty)
    }
}
