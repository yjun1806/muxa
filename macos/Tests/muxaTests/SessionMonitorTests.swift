import Foundation
import Testing
@testable import muxa

/// 세션 관리자의 수집 계층 — 여러 소켓을 합치고, 고아를 표시하고, 무게를 잇는다.
///
/// tmux 셸아웃·커널 조회를 전부 주입받으므로 실제 환경 없이 결정론적으로 검증된다.
@MainActor
struct SessionMonitorTests {
    private let termA = "muxa__P1__term__T1"
    private let termB = "muxa__P2__term__T2"

    /// 표본을 짓는 도우미 — pid → (ppid, 이름, 누적 CPU, footprint).
    private func snapshot(_ entries: [(pid_t, pid_t, String, UInt64, UInt64)],
                          uptime: TimeInterval) -> ProcessSnapshot {
        ProcessSnapshot(samples: entries.reduce(into: [:]) { acc, e in
            acc[e.0] = ProcessSample(pid: e.0, ppid: e.1, name: e.2, cpuNanos: e.3, footprintBytes: e.4)
        }, uptime: uptime)
    }

    /// 실제 tmux·지원 폴더에 닿지 않게 **경계를 모두 주입한다** — 기본값을 쓰면 테스트가
    /// 이 머신의 세션과 파일을 읽어 결과가 환경에 따라 흔들린다.
    ///
    /// `panes`·`clients`를 따로 받아 합친 출력으로 조립한다(실제 tmux가 한 번에 내놓는 꼴).
    private func monitor(sockets: [String],
                         panes: @escaping (String) -> String?,
                         clients: @escaping (String) -> String = { _ in "" },
                         projects: @escaping (String) -> [String: String]? = { _ in nil },
                         snapshots: [ProcessSnapshot] = []) -> SessionMonitor {
        var remaining = snapshots
        return SessionMonitor(
            sockets: { sockets },
            observe: { socket in
                let paneLines = (panes(socket) ?? "").split(separator: "\n")
                    .map { TmuxInventory.paneMarker + $0 }
                let clientLines = clients(socket).split(separator: "\n")
                    .map { TmuxInventory.clientMarker + $0 }
                return (paneLines + clientLines).joined(separator: "\n")
            },
            snapshot: { remaining.isEmpty ? ProcessSnapshot(samples: [:], uptime: 0) : remaining.removeFirst() },
            projects: { projects($0) }
        )
    }

    /// 여러 소켓의 세션이 한 목록으로 합쳐진다 — 그게 이 창의 존재 이유다(앱은 자기 소켓만 본다).
    @Test func mergesSessionsAcrossSockets() async {
        let monitor = monitor(sockets: ["muxa-services", "muxa-services-dev-1"]) { socket in
            socket == "muxa-services" ? "\(termA)|100|0|0|0|500|/a" : "\(termB)|100|0|0|0|600|/b"
        }
        await monitor.refresh()
        #expect(monitor.rows.count == 2)
        #expect(Set(monitor.rows.map(\.socket)) == ["muxa-services", "muxa-services-dev-1"])
        #expect(monitor.hasLoaded)
    }

    /// **응답 없는 소켓은 건너뛰고 나머지는 보여준다.** 실측에서 16개 중 10개가 서버 없는 소켓 파일이었다.
    /// 하나가 실패했다고 목록 전체를 비우면 창이 통째로 쓸모없어진다.
    @Test func skipsFailedSocketsButKeepsRest() async {
        let monitor = monitor(sockets: ["죽은소켓", "muxa-services"]) { socket in
            socket == "muxa-services" ? "\(termA)|100|0|0|0|500|/a" : nil
        }
        await monitor.refresh()
        #expect(monitor.rows.count == 1)
        #expect(monitor.rows.first?.socket == "muxa-services")
    }

    /// **고아 판정은 소켓마다 그 인스턴스의 등록으로 한다.**
    /// 내 등록으로 남의 소켓을 재면 전부 미등록이 되어 표가 온통 고아로 물든다
    /// (실측에서 41개 중 40개가 그렇게 잘못 표시됐다).
    @Test func judgesOrphansPerSocket() async {
        let monitor = monitor(
            sockets: ["muxa-services-dev-1", "muxa-services-dev-2"],
            panes: { socket in
                socket == "muxa-services-dev-1" ? "\(termA)|100|0|0|0|500|/a" : "\(termB)|100|0|0|0|600|/b"
            },
            // dev-1의 주인은 P1을 "웹" 워크스페이스에 등록했고, dev-2의 주인은 다른 것을 등록했다.
            projects: { folder in folder == "muxa-dev-dev-1" ? ["P1": "웹"] : ["딴것": "x"] }
        )
        await monitor.refresh()
        #expect(monitor.rows.first { $0.name == termA }?.isOrphan == false)
        #expect(monitor.rows.first { $0.name == termB }?.isOrphan == true)
    }

    /// **등록을 찾으면 워크스페이스 이름도 함께 온다** — 표를 그 열로 정렬하면 작업 묶음별로 모인다.
    /// 못 찾으면 빈 문자열이고, 그건 곧 고아라는 뜻이라 표에서 소켓 이름으로 대신 보여준다.
    @Test func carriesWorkspaceName() async {
        let monitor = monitor(sockets: ["muxa-services-dev-1"],
                              panes: { _ in "\(termA)|100|0|0|0|500|/a\n\(termB)|100|0|0|0|600|/b" },
                              projects: { _ in ["P1": "웹"] })
        await monitor.refresh()
        #expect(monitor.rows.first { $0.name == termA }?.workspace == "웹")
        #expect(monitor.rows.first { $0.name == termB }?.workspace == "")
    }

    /// 짝이 되는 지원 폴더를 못 읽으면(출처 미상 소켓) 아무것도 고아라 하지 않는다 —
    /// 지어낸 기준으로 "지워도 된다"고 말하는 것이 최악이다.
    @Test func unknownSocketMarksNothing() async {
        let monitor = monitor(sockets: ["muxa_test_1"], panes: { _ in "\(termA)|100|0|0|0|500|/a" })
        await monitor.refresh()
        #expect(monitor.rows.first?.isOrphan == false)
    }

    /// 클라이언트가 없으면 **분리됨** — 어느 화면에도 없이 살아 있는 세션이 이 창의 표적이다.
    @Test func sessionWithNoClientIsDetached() async {
        let monitor = monitor(sockets: ["s"], panes: { _ in "\(termA)|100|0|0|0|500|/a" })
        await monitor.refresh()
        #expect(monitor.rows.first?.attachment == .detached)
    }

    /// 클라이언트가 붙어 있으면 분리가 아니다(조상을 못 찾아도 최소 외부로 본다).
    @Test func sessionWithClientIsNotDetached() async {
        let monitor = monitor(sockets: ["s"], panes: { _ in "\(termA)|100|0|0|0|500|/a" },
                              clients: { _ in "\(self.termA)|4242" })
        await monitor.refresh()
        #expect(monitor.rows.first?.attachment != .detached)
    }

    /// 무게는 행 id로 색인된다 — 소켓이 다르면 같은 세션명도 다른 행이다.
    @Test func indexesWeightByRowIdentity() async {
        let snap = snapshot([(500, 1, "zsh", 0, 1024), (501, 500, "node", 0, 2048)], uptime: 1)
        let monitor = monitor(sockets: ["s"], panes: { _ in "\(termA)|100|0|0|0|500|/a" }, snapshots: [snap])
        await monitor.refresh()
        let row = try! #require(monitor.rows.first)
        #expect(monitor.weight(of: row).footprintBytes == 3072)
        #expect(monitor.weight(of: row).processCount == 2)
    }

    /// 첫 훑기는 CPU를 모르고(직전 표본이 없다), 두 번째부터 델타가 나온다.
    @Test func cpuAppearsOnSecondRefresh() async {
        let first = snapshot([(500, 1, "node", 1_000_000_000, 0)], uptime: 10)
        let second = snapshot([(500, 1, "node", 1_500_000_000, 0)], uptime: 11)
        let monitor = monitor(sockets: ["s"], panes: { _ in "\(termA)|100|0|0|0|500|/a" },
                              snapshots: [first, second])
        await monitor.refresh()
        #expect(monitor.weight(of: try! #require(monitor.rows.first)).cpuPercent == 0)
        await monitor.refresh()
        #expect(abs(monitor.weight(of: try! #require(monitor.rows.first)).cpuPercent - 50) < 0.001)
    }

    /// 모르는 행의 무게를 물으면 0 — 표가 빈 칸 대신 0을 보여줘야 "안에 아무것도 없다"가 읽힌다.
    @Test func unknownRowWeighsZero() async {
        let monitor = monitor(sockets: ["s"]) { _ in "\(termA)|100|0|0|0|500|/a" }
        await monitor.refresh()
        let ghost = TmuxSessionRow(socket: "x", name: "y", kind: .foreign, projectId: nil,
                                   isDead: false, isAttached: false, createdAt: nil, path: "", panePid: nil)
        #expect(monitor.weight(of: ghost) == .zero)
    }

    /// **stop 뒤에는 진행 중이던 훑기의 결과를 쓰지 않는다.**
    /// 창을 닫는 순간 await 중이던 refresh가 재개해 목록을 되살리면, 닫힌 창의 폴링이 계속 도는 것처럼
    /// 보인다(ServiceMonitor가 세대 카운터를 둔 것과 같은 이유).
    ///
    /// 소켓을 읽는 **도중에** 창이 닫히는 상황을 주입으로 재현한다 — Task 스케줄 순서에 기대면
    /// 이 테스트 자체가 간헐적으로 통과한다.
    @Test func stopDiscardsInFlightRefresh() async {
        var monitorRef: SessionMonitor?
        let monitor = SessionMonitor(
            sockets: { ["s"] },
            observe: { [termA] _ in
                monitorRef?.stop() // 읽는 사이에 창이 닫혔다
                return TmuxInventory.paneMarker + "\(termA)|100|0|0|0|500|/a"
            },
            snapshot: { ProcessSnapshot(samples: [:], uptime: 0) }
        )
        monitorRef = monitor
        await monitor.refresh()
        #expect(monitor.rows.isEmpty)
    }

    /// **소켓 순서가 결과 순서다.** 동시에 훑으면 완료 순서가 비결정적이라, 정렬하지 않으면
    /// 폴링(2초)마다 표의 행이 뒤바뀌어 클릭이 빗나간다.
    @Test func preservesSocketOrderDespiteConcurrency() async {
        let monitor = monitor(sockets: ["muxa-services", "muxa-services-dev-1"]) { socket in
            socket == "muxa-services" ? "\(termA)|100|0|0|0|500|/a" : "\(termB)|100|0|0|0|600|/b"
        }
        await monitor.refresh()
        #expect(monitor.rows.map(\.socket) == ["muxa-services", "muxa-services-dev-1"])
    }

    /// 창을 닫으면 목록을 비운다 — 다시 열 때 낡은 목록이 잠깐 보이면 그걸 근거로 죽인다.
    @Test func stopClearsRows() async {
        let monitor = monitor(sockets: ["s"]) { _ in "\(termA)|100|0|0|0|500|/a" }
        await monitor.refresh()
        #expect(monitor.rows.count == 1)
        monitor.stop()
        #expect(monitor.rows.isEmpty)
        #expect(!monitor.hasLoaded)
    }

    /// 소켓이 하나도 없어도 죽지 않는다(tmux를 안 쓰는 머신).
    @Test func survivesWithNoSockets() async {
        let monitor = monitor(sockets: []) { _ in nil }
        await monitor.refresh()
        #expect(monitor.rows.isEmpty)
        #expect(monitor.hasLoaded)
    }
}
