import XCTest
@testable import muxa

/// 명령 이력 — 병합·상한·섹션 분류. 스크립트+일회용 통합의 근간이라 규칙을 못 박는다.
final class CommandHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func script(_ name: String, _ command: String) -> Script {
        Script(id: name, name: name, command: command, cwd: nil)
    }

    /// 새 명령은 맨 앞에 추가된다.
    func testRecordAddsNewAtFront() {
        let h = CommandHistory.record([], command: "ls", name: "ls", cwd: nil, now: t0)
        XCTAssertEqual(h.map(\.command), ["ls"])
        XCTAssertEqual(h.first?.runCount, 1)
        XCTAssertEqual(h.first?.lastRunAt, t0)
    }

    /// 같은 명령 재실행 — 갱신하며 맨 앞으로, runCount 증가, 중복 없음.
    func testRecordMergesDuplicateToFront() {
        var h = CommandHistory.record([], command: "a", name: "a", cwd: nil, now: at(0))
        h = CommandHistory.record(h, command: "b", name: "b", cwd: nil, now: at(1))
        h = CommandHistory.record(h, command: "a", name: "a", cwd: nil, now: at(2)) // a 재실행
        XCTAssertEqual(h.map(\.command), ["a", "b"], "재실행한 a가 맨 앞으로")
        XCTAssertEqual(h.first?.runCount, 2, "runCount 누적")
        XCTAssertEqual(h.first?.lastRunAt, at(2), "lastRunAt 갱신")
    }

    /// 마지막 실행 기준으로 name·cwd가 갱신된다.
    func testRecordUpdatesNameAndCwd() {
        var h = CommandHistory.record([], command: "cmd", name: "old", cwd: "/a", now: at(0))
        h = CommandHistory.record(h, command: "cmd", name: "new", cwd: "/b", now: at(1))
        XCTAssertEqual(h.first?.name, "new")
        XCTAssertEqual(h.first?.cwd, "/b")
    }

    /// 100개 상한 — 101번째를 넣으면 가장 오래된 것이 밀려난다.
    func testRecordCapsAtLimit() {
        var h: [CommandHistoryEntry] = []
        for i in 0..<CommandHistory.limit {
            h = CommandHistory.record(h, command: "c\(i)", name: "c\(i)", cwd: nil, now: at(TimeInterval(i)))
        }
        XCTAssertEqual(h.count, CommandHistory.limit)
        h = CommandHistory.record(h, command: "new", name: "new", cwd: nil, now: at(1000))
        XCTAssertEqual(h.count, CommandHistory.limit, "상한 유지")
        XCTAssertEqual(h.first?.command, "new", "새 것은 맨 앞")
        XCTAssertFalse(h.contains { $0.command == "c0" }, "가장 오래된 c0이 밀려남")
    }

    /// 섹션 분류 — 등록은 등록 섹션(+lastRun), 미등록만 히스토리.
    func testSectionsSplitRegisteredAndHistory() {
        let history = [
            CommandHistoryEntry(command: "make build", name: "build", cwd: nil, lastRunAt: at(2), runCount: 3),
            CommandHistoryEntry(command: "pnpm i", name: "pnpm i", cwd: nil, lastRunAt: at(1), runCount: 1),
        ]
        let registered = [script("build", "make build")] // "make build"는 등록됨
        let (reg, hist) = CommandHistory.sections(registered: registered, history: history)

        XCTAssertEqual(reg.count, 1)
        XCTAssertEqual(reg.first?.script.name, "build")
        XCTAssertEqual(reg.first?.lastRunAt, at(2), "등록 명령의 lastRun을 이력에서 가져옴")
        XCTAssertEqual(hist.map(\.command), ["pnpm i"], "등록된 make build는 히스토리에서 빠지고 미등록만 남음")
    }

    /// 등록됐지만 한 번도 안 돌린 명령은 lastRunAt이 nil.
    func testRegisteredNeverRunHasNilLastRun() {
        let (reg, _) = CommandHistory.sections(registered: [script("test", "make test")], history: [])
        XCTAssertNil(reg.first?.lastRunAt)
    }

    private func located(_ id: String, _ command: String) -> LocatedScript {
        LocatedScript(script: Script(id: id, name: command, command: command, cwd: nil),
                      workspaceId: "w", workspaceName: "w", projectId: "p", projectName: "p", cwd: "/")
    }

    /// 명령의 실행 상태 — 그 command로 실행된 인스턴스 중 가장 최근 run.
    func testRunStateMatchesLatestInstance() {
        let instances = [located("i1", "pnpm i"), located("i2", "pnpm i"), located("x", "ls")]
        let runs: [String: ScriptRun] = [
            "i1": ScriptRun(scriptId: "i1", projectId: "p", name: "pnpm i", startedAt: at(1), state: .running),
            "i2": ScriptRun(scriptId: "i2", projectId: "p", name: "pnpm i", startedAt: at(5),
                            state: .finished(code: 0, duration: 2)),
        ]
        let st = CommandHistory.runState(command: "pnpm i", instances: instances, runs: runs)
        XCTAssertEqual(st?.scriptId, "i2", "startedAt이 가장 최근인 i2")
    }

    /// 그 명령의 실행 인스턴스가 없으면 nil(재시작 후·과거 기록만).
    func testRunStateNilWhenNoInstance() {
        XCTAssertNil(CommandHistory.runState(command: "make build",
                                             instances: [located("i", "pnpm i")], runs: [:]))
    }
}
