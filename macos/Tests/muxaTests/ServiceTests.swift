import XCTest
@testable import muxa

/// 서비스(장수 프로세스) 순수 로직 — tmux 출력 파싱·세션명 규약·고아 판정·포트 추출.
/// 부작용(tmux 셸아웃)은 TmuxService 경계에 있고, 여기서는 순수 함수만 검증한다.
final class ServiceTests: XCTestCase {
    // MARK: 세션명 규약 — muxa__<projectId>__<serviceId>

    func testSessionNameRoundTrip() {
        let name = ServiceSession.name(projectId: "P1", serviceId: "S1")
        XCTAssertEqual(name, "muxa__P1__S1")
        let parsed = ServiceSession.parse(name)
        XCTAssertEqual(parsed?.projectId, "P1")
        XCTAssertEqual(parsed?.serviceId, "S1")
    }

    /// UUID(하이픈 포함, 언더스코어 없음)를 써도 왕복이 깨지지 않는다.
    func testSessionNameRoundTripWithUUID() {
        let pid = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let sid = "A1B2C3D4-0000-1111-2222-333344445555"
        let parsed = ServiceSession.parse(ServiceSession.name(projectId: pid, serviceId: sid))
        XCTAssertEqual(parsed?.projectId, pid)
        XCTAssertEqual(parsed?.serviceId, sid)
    }

    /// muxa 소유가 아닌 세션은 파싱을 거부한다 — 남의 세션을 건드리지 않기 위한 1차 방어선.
    func testForeignSessionIsRejected() {
        XCTAssertNil(ServiceSession.parse("my-work"))
        XCTAssertNil(ServiceSession.parse("muxa"))
        XCTAssertNil(ServiceSession.parse("muxa__onlyproject"))
        XCTAssertNil(ServiceSession.parse("notmuxa__P__S"))
    }

    // MARK: list-panes 출력 파싱 — 상태의 진실 원천(서피스 렌더 불필요)

    func testParsePanesRunningAndDead() {
        // 실측 포맷: '#{session_name}|#{pane_dead}|#{pane_dead_status}'
        let raw = """
        muxa__P__web|0|
        muxa__P__api|1|1
        """
        let states = ServiceSession.parsePanes(raw)
        XCTAssertEqual(states["muxa__P__web"], .running)
        XCTAssertEqual(states["muxa__P__api"], .exited(code: 1))
    }

    func testParsePanesNormalExitIsZero() {
        XCTAssertEqual(ServiceSession.parsePanes("muxa__P__job|1|0")["muxa__P__job"], .exited(code: 0))
    }

    /// dead=1 인데 status가 비어 있으면(신호 종료 등) 코드를 모른다 — -1로 두되 exited로는 확정한다.
    func testParsePanesDeadWithoutStatus() {
        XCTAssertEqual(ServiceSession.parsePanes("muxa__P__x|1|")["muxa__P__x"], .exited(code: -1))
    }

    func testParsePanesIgnoresGarbage() {
        let raw = """

        garbage line without pipes
        muxa__P__web|0|
        |0|
        """
        let states = ServiceSession.parsePanes(raw)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states["muxa__P__web"], .running)
    }

    func testParsePanesEmpty() {
        XCTAssertTrue(ServiceSession.parsePanes("").isEmpty)
    }

    // MARK: 고아 판정 — 좀비 tmux 세션 정리 (ScrollbackStore.orphans 와 같은 원칙: 의심되면 안 지운다)

    func testOrphanIsUnregisteredMuxaSession() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__P__web", "muxa__P__ghost"],
                                             liveServiceIds: ["web"])
        XCTAssertEqual(orphans, ["muxa__P__ghost"])
    }

    /// muxa 소유가 아닌 세션은 절대 고아로 보지 않는다 — 사용자의 다른 tmux 작업을 죽이면 안 된다.
    func testForeignSessionIsNeverOrphan() {
        let orphans = ServiceSession.orphans(sessions: ["my-work", "irssi", "muxa__P__web"],
                                             liveServiceIds: ["web"])
        XCTAssertTrue(orphans.isEmpty)
    }

    func testNoRegisteredServicesMakesAllMuxaSessionsOrphan() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__P__a", "muxa__P__b"], liveServiceIds: [])
        XCTAssertEqual(Set(orphans), ["muxa__P__a", "muxa__P__b"])
    }

    // MARK: 포트 추출 — 칩에 ':3000'을 띄우기 위한 최소 매칭. 못 뽑으면 nil(이름만 표시).

    func testExtractPortFromViteOutput() {
        let log = """
        [vite] starting...
          ➜  Local:   http://localhost:3000/
        [vite] ready in 320 ms
        """
        XCTAssertEqual(ServiceSession.extractPort(log), 3000)
    }

    func testExtractPortFromBindAddresses() {
        XCTAssertEqual(ServiceSession.extractPort("Listening on 127.0.0.1:8080"), 8080)
        XCTAssertEqual(ServiceSession.extractPort("bound to 0.0.0.0:5432"), 5432)
    }

    /// 가장 최근(마지막) 매치를 쓴다 — 재시작 시 옛 포트가 아니라 지금 포트를 보여줘야 한다.
    func testExtractPortUsesLastMatch() {
        let log = """
        http://localhost:3000/
        Port in use, retrying...
        http://localhost:3001/
        """
        XCTAssertEqual(ServiceSession.extractPort(log), 3001)
    }

    /// 시각(16:27:38)을 포트로 오인하지 않는다 — 호스트가 앞에 붙은 경우만 인정한다(오탐 방지).
    func testTimestampIsNotAPort() {
        XCTAssertNil(ServiceSession.extractPort("Pane is dead (status 1, Mon Jul 13 16:27:38 2026)"))
        XCTAssertNil(ServiceSession.extractPort("[vite] ready in 320 ms"))
    }

    func testExtractPortNoneWhenAbsent() {
        XCTAssertNil(ServiceSession.extractPort(""))
        XCTAssertNil(ServiceSession.extractPort("compiling..."))
    }
}
