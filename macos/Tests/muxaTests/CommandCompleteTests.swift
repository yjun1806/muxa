import XCTest
@testable import muxa

/// 명령 이름 자동완성(순수) — 정규화 순서·접두 우선·정확일치 제외·상한. A안(muxa 자체 사전) 근간.
final class CommandCompleteTests: XCTestCase {
    private func fav(_ command: String, _ name: String? = nil) -> CommandEntry {
        CommandEntry(command: command, name: name, cwd: nil, favorite: true, executions: [])
    }
    private func hist(_ command: String) -> CommandEntry {
        CommandEntry(command: command, name: nil, cwd: nil, favorite: false,
                     executions: [CommandExecution(id: "x", startedAt: Date(timeIntervalSince1970: 0),
                                                   exitCode: 0, duration: nil)])
    }
    private func scr(_ name: String, _ command: String) -> DiscoveredScript {
        DiscoveredScript(name: name, command: command, source: "package.json")
    }

    /// 정규화 — 즐겨찾기 → 발견 → 히스토리 순, 소스·라벨·아이콘이 채워진다.
    func testCandidatesOrderAndFields() {
        let c = CommandComplete.candidates(favorites: [fav("make build", "build")],
                                           scripts: [scr("dev", "pnpm run dev")],
                                           history: [hist("brew install jq")])
        XCTAssertEqual(c.map(\.command), ["make build", "pnpm run dev", "brew install jq"])
        XCTAssertEqual(c[0].label, "build")          // 즐겨찾기 이름
        XCTAssertEqual(c[0].source, "즐겨찾기")
        XCTAssertEqual(c[1].label, "dev")            // 스크립트 이름
        XCTAssertEqual(c[1].source, "package.json")
        XCTAssertEqual(c[2].source, "최근")
    }

    /// 빈 입력 → 후보 없음(런처: 포커스만으로 드롭다운 안 띄움).
    func testEmptyInputNoMatch() {
        let c = CommandComplete.candidates(favorites: [fav("pnpm dev")], scripts: [], history: [])
        XCTAssertTrue(CommandComplete.match("", in: c).isEmpty)
        XCTAssertTrue(CommandComplete.match("   ", in: c).isEmpty)
    }

    /// 접두 매칭이 부분 매칭보다 앞. (query "dev": 접두 "dev script" > 부분 "pnpm dev")
    func testPrefixBeforeContains() {
        let c = CommandComplete.candidates(favorites: [fav("pnpm dev"), fav("dev-server")],
                                           scripts: [], history: [])
        // "pnpm dev"는 label=command="pnpm dev"(부분), "dev-server"는 접두.
        XCTAssertEqual(CommandComplete.match("dev", in: c).map(\.command), ["dev-server", "pnpm dev"])
    }

    /// 라벨(친근 이름)로도 매칭 — "de"가 스크립트 이름 "dev"에 걸린다.
    func testMatchesLabel() {
        let c = CommandComplete.candidates(favorites: [], scripts: [scr("dev", "pnpm run dev")], history: [])
        XCTAssertEqual(CommandComplete.match("de", in: c).map(\.command), ["pnpm run dev"])
    }

    /// 정확히 다 친 명령은 제외(드롭다운이 완성된 입력을 덮지 않게).
    func testExactTypedExcluded() {
        let c = CommandComplete.candidates(favorites: [fav("pnpm dev")], scripts: [], history: [])
        XCTAssertTrue(CommandComplete.match("pnpm dev", in: c).isEmpty)
        XCTAssertTrue(CommandComplete.match("PNPM DEV", in: c).isEmpty, "대소문자 무시")
    }

    /// 대소문자 무시 매칭.
    func testCaseInsensitive() {
        let c = CommandComplete.candidates(favorites: [fav("Make Build")], scripts: [], history: [])
        XCTAssertEqual(CommandComplete.match("make", in: c).map(\.command), ["Make Build"])
    }

    /// 상한 — 8개까지만.
    func testLimit() {
        let favs = (0..<20).map { fav("cmd\($0)") }
        let c = CommandComplete.candidates(favorites: favs, scripts: [], history: [])
        XCTAssertEqual(CommandComplete.match("cmd", in: c).count, CommandComplete.limit)
    }
}
