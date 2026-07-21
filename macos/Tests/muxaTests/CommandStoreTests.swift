import XCTest
@testable import muxa

/// 명령 모델(v2) — 실행 기록·즐겨찾기·cwd·섹션·10개 상한. 요구 재정의(실행→즐겨찾기·명령당 내역)의 근간.
final class CommandStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// 새 명령은 엔트리를 만들고 실행 하나를 얹는다(favorite=false).
    func testRecordStartCreatesEntry() {
        let (e, dropped) = CommandStore.recordStart([], command: "pnpm dev", cwd: "/p", name: nil,
                                                    execId: "x1", now: at(0))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].command, "pnpm dev")
        XCTAssertEqual(e[0].cwd, "/p")
        XCTAssertFalse(e[0].favorite)
        XCTAssertEqual(e[0].executions.map(\.id), ["x1"])
        XCTAssertTrue(dropped.isEmpty)
    }

    /// 같은 명령 재실행 — 같은 엔트리에 실행이 앞으로 쌓이고 cwd가 갱신된다.
    func testRecordStartMergesSameCommand() {
        var (e, _) = CommandStore.recordStart([], command: "a", cwd: "/x", name: nil, execId: "1", now: at(0))
        (e, _) = CommandStore.recordStart(e, command: "a", cwd: "/y", name: nil, execId: "2", now: at(1))
        XCTAssertEqual(e.count, 1, "같은 명령은 한 엔트리")
        XCTAssertEqual(e[0].executions.map(\.id), ["2", "1"], "최신이 앞")
        XCTAssertEqual(e[0].cwd, "/y", "cwd 갱신")
        XCTAssertEqual(e[0].runCount, 2)
    }

    /// 명령당 10개 상한 — 11번째 실행 시 가장 오래된 것이 dropped로 빠진다.
    func testExecLimitDropsOldest() {
        var e: [CommandEntry] = []
        for i in 0..<CommandStore.execLimit {
            (e, _) = CommandStore.recordStart(e, command: "a", cwd: nil, name: nil, execId: "e\(i)", now: at(TimeInterval(i)))
        }
        let (e2, dropped) = CommandStore.recordStart(e, command: "a", cwd: nil, name: nil, execId: "new", now: at(100))
        XCTAssertEqual(e2[0].executions.count, CommandStore.execLimit, "상한 유지")
        XCTAssertEqual(dropped, ["e0"], "가장 오래된 e0이 밀려남(로그 삭제 대상)")
        XCTAssertEqual(e2[0].executions.first?.id, "new")
    }

    /// 완료 반영 — execId의 실행에 exitCode·duration이 채워진다.
    func testRecordFinish() {
        var (e, _) = CommandStore.recordStart([], command: "a", cwd: nil, name: nil, execId: "1", now: at(0))
        e = CommandStore.recordFinish(e, execId: "1", exitCode: 0, duration: 2.5)
        XCTAssertEqual(e[0].executions[0].exitCode, 0)
        XCTAssertEqual(e[0].executions[0].duration, 2.5)
        XCTAssertTrue(e[0].executions[0].isFinished)
        XCTAssertFalse(e[0].executions[0].isFailure)
    }

    /// 실패 확정은 code≠0만 — nil(미상)은 실패로 단정 안 함.
    func testFailureOnlyWhenNonZero() {
        var (e, _) = CommandStore.recordStart([], command: "a", cwd: nil, name: nil, execId: "1", now: at(0))
        e = CommandStore.recordFinish(e, execId: "1", exitCode: 2, duration: nil)
        XCTAssertTrue(e[0].executions[0].isFailure)
        let running = CommandExecution(id: "r", startedAt: at(0), exitCode: nil, duration: nil)
        XCTAssertFalse(running.isFailure, "미상은 실패 아님")
    }

    /// 즐겨찾기 토글 — 켜면 favorites, 끄면 history.
    func testToggleFavoriteMovesSections() {
        var (e, _) = CommandStore.recordStart([], command: "a", cwd: nil, name: nil, execId: "1", now: at(0))
        XCTAssertEqual(CommandStore.sections(e).history.map(\.command), ["a"])
        e = CommandStore.toggleFavorite(e, command: "a")
        let s = CommandStore.sections(e)
        XCTAssertEqual(s.favorites.map(\.command), ["a"])
        XCTAssertTrue(s.history.isEmpty)
    }

    /// 히스토리는 최근 실행순.
    func testHistorySortedByRecency() {
        var (e, _) = CommandStore.recordStart([], command: "old", cwd: nil, name: nil, execId: "1", now: at(0))
        (e, _) = CommandStore.recordStart(e, command: "new", cwd: nil, name: nil, execId: "2", now: at(10))
        XCTAssertEqual(CommandStore.sections(e).history.map(\.command), ["new", "old"])
    }

    /// cwd 변경·명령 삭제(로그 dropped 반환).
    func testSetCwdAndRemove() {
        var (e, _) = CommandStore.recordStart([], command: "a", cwd: "/x", name: nil, execId: "1", now: at(0))
        e = CommandStore.setCwd(e, command: "a", cwd: "/new")
        XCTAssertEqual(e[0].cwd, "/new")
        let (e2, dropped) = CommandStore.remove(e, command: "a")
        XCTAssertTrue(e2.isEmpty)
        XCTAssertEqual(dropped, ["1"], "지운 명령의 실행 로그도 정리 대상")
    }
}
