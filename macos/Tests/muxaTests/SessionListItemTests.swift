import Foundation
import Testing
@testable import muxa

/// 표에 뿌릴 값의 판정(순수) — 이름·필터·검색·요약.
///
/// 세션명은 UUID 두 개라 사람이 못 읽는다. 표가 무엇을 "이름"으로 삼느냐가 이 창의 쓸모를 정한다.
struct SessionListItemTests {
    private func item(name: String = "muxa__P1__term__T1", path: String = "/Users/yj/Documents/muxa",
                      kind: TmuxSessionRow.Kind = .terminal, dead: Bool = false,
                      attachment: SessionAttachment = .detached,
                      orphan: Bool = false, weight: SessionWeight = .zero) -> SessionListItem {
        var row = TmuxSessionRow(socket: "muxa-services", name: name, kind: kind, projectId: "P1",
                                 isDead: dead, isAttached: attachment != .detached,
                                 createdAt: nil, path: path, panePid: 1)
        row.isOrphan = orphan
        row.attachment = attachment
        return SessionListItem(row: row, weight: weight)
    }

    /// **폴더명이 이름이다.** 실측에서 세션을 구분해준 건 UUID가 아니라 `citadel-admin`·`gitNote`였다.
    @Test func titleIsFolderName() {
        #expect(item(path: "/Users/yj/Documents/private/muxa").title == "muxa")
        #expect(item(path: "/Users/yj").title == "yj")
    }

    /// 죽은 pane엔 경로가 없다 — 그때도 빈 칸을 두지 않는다.
    @Test func titleFallsBackWhenPathMissing() {
        #expect(!item(path: "", dead: true).title.isEmpty)
    }

    /// 필터는 종류로 가른다. 스크립트와 서비스는 한 칸에 묶는다 — 둘 다 "돌리고 끝나는 것"이고,
    /// 사용자에게는 터미널이냐 아니냐가 더 큰 구분이다.
    @Test func filtersByKind() {
        let term = item(kind: .terminal)
        let script = item(kind: .script)
        let service = item(kind: .service)
        #expect(SessionFilter.all.matches(term))
        #expect(SessionFilter.terminal.matches(term))
        #expect(!SessionFilter.terminal.matches(script))
        #expect(SessionFilter.task.matches(script))
        #expect(SessionFilter.task.matches(service))
        #expect(!SessionFilter.task.matches(term))
    }

    /// 고아 탭은 "확인해볼 것"만 모은다 — 이 창을 만든 이유가 그 목록이다.
    @Test func orphanFilterSelectsMarkedOnly() {
        #expect(SessionFilter.orphan.matches(item(orphan: true)))
        #expect(!SessionFilter.orphan.matches(item(orphan: false)))
    }

    /// 검색은 이름·경로·안에 도는 것을 함께 훑는다. "esbuild가 어디서 돌지"로 찾을 수 있어야 한다.
    @Test func searchSpansTitlePathAndLabels() {
        let it = item(path: "/Users/yj/work/admin",
                      weight: SessionWeight(cpuPercent: 0, footprintBytes: 0, processCount: 1,
                                            labels: ["esbuild", "node"]))
        #expect(it.matches(search: "admin"))
        #expect(it.matches(search: "esbuild"))
        #expect(it.matches(search: "/work/"))
        #expect(it.matches(search: "")) // 빈 검색어는 전부 통과
        #expect(!it.matches(search: "없는말"))
    }

    /// 검색은 대소문자를 가리지 않는다.
    @Test func searchIsCaseInsensitive() {
        #expect(item(path: "/x/GitBaro").matches(search: "gitbaro"))
    }

    /// 하단 요약은 세 숫자만 말한다 — 전체·종료됨·고아.
    @Test func summarizesCounts() {
        let summary = SessionSummary(items: [
            item(dead: false, orphan: true),
            item(dead: true, orphan: true),
            item(dead: true, orphan: false),
        ])
        #expect(summary.total == 3)
        #expect(summary.dead == 2)
        #expect(summary.orphan == 2)
    }

    /// 메모리는 사람이 읽는 단위로. 0이면 빈 칸이 아니라 0이어야 "안에 아무것도 없다"가 읽힌다.
    @Test func formatsMemory() {
        #expect(item(weight: .zero).memoryText == "0 MB")
        let big = SessionWeight(cpuPercent: 0, footprintBytes: 3_800_000_000, processCount: 1, labels: [])
        #expect(item(weight: big).memoryText.contains("GB"))
    }

    /// CPU는 소수 한 자리. 첫 훑기의 0도 그대로 보여준다(모른다고 빈 칸을 두면 0과 구분이 안 된다).
    @Test func formatsCPU() {
        #expect(item(weight: .zero).cpuText == "0.0")
        let busy = SessionWeight(cpuPercent: 12.34, footprintBytes: 0, processCount: 1, labels: [])
        #expect(item(weight: busy).cpuText == "12.3")
    }

    /// 죽음이 먼저다 — 죽은 pane에 클라이언트가 붙어 있는 경우가 있어, 연결을 앞세우면
    /// 종료된 세션이 "이 앱"으로 보인다.
    @Test func statusPrefersDeath() {
        #expect(item(dead: true, attachment: .thisApp).statusText == "종료됨")
    }

    /// **터미널**은 살아 있으면 누가 보고 있는지를 말한다 — 탭에 붙어 있는 게 그쪽의 정상이라
    /// "안 붙어 있음"이 곧 정보다.
    @Test func terminalStatusNamesWhoIsWatching() {
        #expect(item(attachment: .thisApp).statusText == "이 앱")
        #expect(item(attachment: .otherApp(name: "muxa-dev-main", pid: 99000)).statusText == "muxa-dev-main")
        #expect(item(attachment: .external).statusText == "외부 터미널")
        #expect(item(attachment: .detached).statusText == "분리됨")
    }

    /// **스크립트·서비스는 attach가 상태가 아니다.** `new-session -d`로 띄우므로 붙어 있지 않은 게
    /// 기본이고(실측: 스크립트 12개 중 연결된 것 0개), 거기에 "분리됨"이라 쓰면 멀쩡히 도는
    /// dev 서버가 문제처럼 보인다. 그쪽의 상태는 프로세스가 사는가다.
    @Test func backgroundKindsReportRunning() {
        #expect(item(kind: .script, attachment: .detached).statusText == "실행 중")
        #expect(item(kind: .service, attachment: .detached).statusText == "실행 중")
        #expect(item(kind: .script, dead: true, attachment: .detached).statusText == "종료됨")
    }

    /// **숨은 것 = 붙을 탭조차 없이 살아 있는 터미널.** 이 창의 출발점이 정확히 이 집합이다.
    @Test func hiddenIsUnattachedTerminalOnly() {
        #expect(item(attachment: .detached).isHidden)
        #expect(!item(attachment: .thisApp).isHidden)
        #expect(!item(dead: true, attachment: .detached).isHidden) // 되찾을 것이 없다
        #expect(SessionFilter.hidden.matches(item(attachment: .detached)))
        #expect(!SessionFilter.hidden.matches(item(attachment: .external)))
    }

    /// **미연결은 숨은 것이 아니다** — 탭이 있으니 그리로 가면 다시 붙는다.
    /// 앱을 막 켰을 때가 그렇고, 그걸 "숨은 터미널"에 넣으면 정상 상태가 목록을 채운다.
    @Test func idleTabIsNotHidden() {
        #expect(!item(attachment: .idleTab).isHidden)
        #expect(!SessionFilter.hidden.matches(item(attachment: .idleTab)))
        #expect(item(attachment: .idleTab).statusText == "미연결")
    }

    /// **백그라운드로 도는 스크립트·서비스는 숨은 것이 아니다.**
    /// 화면에 없는 게 그들의 정상이라 여기 넣으면 목록이 정상으로 차고, 진짜 찾아야 할 것이 묻힌다.
    /// 그쪽의 이상("등록 없이 돎")은 고아 탭이 잡는다.
    @Test func backgroundKindsAreNotHidden() {
        #expect(!item(kind: .script, attachment: .detached).isHidden)
        #expect(!item(kind: .service, attachment: .detached).isHidden)
    }
}
