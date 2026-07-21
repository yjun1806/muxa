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

    /// 실행 안 한 발견 스크립트를 ☆ 하면 엔트리가 없으므로 즐겨찾기로 새로 만든다.
    func testToggleFavoriteCreatesForDiscovered() {
        let e = CommandStore.toggleFavorite([], command: "pnpm dev", name: "dev", cwd: "/p")
        XCTAssertEqual(e.count, 1)
        XCTAssertTrue(e[0].favorite)
        XCTAssertEqual(e[0].name, "dev")
        XCTAssertTrue(e[0].executions.isEmpty, "아직 실행 전이므로 내역 없음")
    }

    private func disc(_ name: String, _ command: String) -> DiscoveredScript {
        DiscoveredScript(name: name, command: command, source: "package.json")
    }

    /// 세 섹션 — 한 명령은 한 섹션에만(즐겨찾기 > 발견 > 히스토리 우선, 중복 제거).
    func testPanelSectionsDedup() {
        var e: [CommandEntry] = []
        (e, _) = CommandStore.recordStart(e, command: "brew install jq", cwd: nil, name: nil, execId: "1", now: at(3)) // 즉석
        (e, _) = CommandStore.recordStart(e, command: "pnpm dev", cwd: nil, name: nil, execId: "2", now: at(2))       // 발견 명령을 실행함
        e = CommandStore.toggleFavorite(e, command: "pnpm dev")                                                        // 즐겨찾기로
        let discovered = [disc("dev", "pnpm dev"), disc("build", "pnpm build")]
        let s = CommandStore.panelSections(e, discovered: discovered)

        XCTAssertEqual(s.favorites.map(\.command), ["pnpm dev"], "즐겨찾기")
        XCTAssertEqual(s.projectScripts.map(\.command), ["pnpm build"], "발견 중 즐겨찾기 아닌 것만(dev는 빠짐)")
        XCTAssertEqual(s.history.map(\.command), ["brew install jq"], "발견도 즐겨찾기도 아닌 즉석만")
    }

    /// 발견 스크립트를 아직 안 돌렸어도 프로젝트 스크립트 섹션에 전부 나온다(요구 1).
    func testPanelSectionsShowsAllDiscovered() {
        let s = CommandStore.panelSections([], discovered: [disc("dev", "pnpm dev"), disc("test", "pnpm test")])
        XCTAssertEqual(s.projectScripts.map(\.name), ["dev", "test"])
        XCTAssertTrue(s.favorites.isEmpty)
        XCTAssertTrue(s.history.isEmpty)
    }

    /// 히스토리는 최근 실행순.
    func testHistorySortedByRecency() {
        var (e, _) = CommandStore.recordStart([], command: "old", cwd: nil, name: nil, execId: "1", now: at(0))
        (e, _) = CommandStore.recordStart(e, command: "new", cwd: nil, name: nil, execId: "2", now: at(10))
        XCTAssertEqual(CommandStore.sections(e).history.map(\.command), ["new", "old"])
    }

    /// v1→v2 이관 — 등록 스크립트=favorite, 히스토리=비favorite, 둘 다 비면 nil.
    func testMigrate() {
        let scripts = [Script(id: "s1", name: "web", command: "pnpm dev", cwd: "/p")]
        let history = [CommandHistoryEntry(command: "pnpm test", name: "pnpm test", cwd: nil,
                                           lastRunAt: at(5), runCount: 2)]
        let m = CommandStore.migrate(scripts: scripts, history: history)!
        XCTAssertEqual(m.first { $0.command == "pnpm dev" }?.favorite, true, "등록→즐겨찾기")
        XCTAssertEqual(m.first { $0.command == "pnpm dev" }?.name, "web", "이름 보존")
        XCTAssertEqual(m.first { $0.command == "pnpm test" }?.favorite, false, "히스토리→비즐겨찾기")
        XCTAssertNil(CommandStore.migrate(scripts: [], history: []), "둘 다 비면 nil")
    }

    /// 같은 명령이 등록·히스토리 양쪽이면 한 엔트리로 묶고 favorite을 켠다.
    func testMigrateMergesSameCommand() {
        let scripts = [Script(id: "s", name: "build", command: "make build", cwd: nil)]
        let history = [CommandHistoryEntry(command: "make build", name: "make build", cwd: nil,
                                           lastRunAt: at(1), runCount: 1)]
        let m = CommandStore.migrate(scripts: scripts, history: history)!
        XCTAssertEqual(m.count, 1, "한 엔트리로 병합")
        XCTAssertTrue(m[0].favorite)
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
