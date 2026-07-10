import XCTest
@testable import muxa

/// MuxaConfig 순수 파서 검증 — 설정 표면의 단일 진실 원천.
final class MuxaConfigTests: XCTestCase {
    func testEmptyIsDefaults() {
        XCTAssertEqual(MuxaConfig.parse(""), MuxaConfig.defaults)
    }

    func testParsePairsSkipsCommentsBlanksAndNoEquals() {
        let pairs = MuxaConfig.parsePairs("""
        # comment
        confirm_quit = false

        no equals here
        command_finished_threshold_sec = 3
        """)
        XCTAssertEqual(pairs["confirm_quit"], "false")
        XCTAssertEqual(pairs["command_finished_threshold_sec"], "3")
        XCTAssertNil(pairs["no equals here"])
        XCTAssertNil(pairs["# comment"])
    }

    func testParsePairsLastWins() {
        XCTAssertEqual(MuxaConfig.parsePairs("k = 1\nk = 2")["k"], "2")
    }

    func testBoolLenientParsing() {
        for on in ["true", "yes", "on", "1"] {
            XCTAssertFalse(MuxaConfig.parse("confirm_quit = \(on)").confirmQuit == false, "\(on) → true")
        }
        for off in ["false", "no", "off", "0"] {
            XCTAssertFalse(MuxaConfig.parse("confirm_quit = \(off)").confirmQuit, "\(off) → false")
        }
        // 인식 못 하는 값 → 기본값(true) 유지
        XCTAssertTrue(MuxaConfig.parse("confirm_quit = maybe").confirmQuit)
    }

    func testThresholdParsingAndNsConversion() {
        XCTAssertEqual(MuxaConfig.parse("command_finished_threshold_sec = 2.5").commandFinishedThresholdSec, 2.5)
        XCTAssertEqual(MuxaConfig.parse("command_finished_threshold_sec = 2").commandFinishedThresholdNs, 2_000_000_000)
        // 음수는 0으로 클램프
        XCTAssertEqual(MuxaConfig.parse("command_finished_threshold_sec = -5").commandFinishedThresholdNs, 0)
    }

    func testExtractKeybindings() {
        let kb = MuxaConfig.parse("keybind.new_terminal = cmd+t\nkeybind. = ignored\nconfirm_quit = true").keybindings
        XCTAssertEqual(kb["new_terminal"], "cmd+t")
        XCTAssertNil(kb[""])            // 빈 액션 무시
        XCTAssertNil(kb["confirm_quit"]) // keybind. 접두 아닌 건 제외
    }

    func testAgentResumeParsing() {
        XCTAssertEqual(MuxaConfig.parse("agent_resume = auto").agentResume, .auto)
        XCTAssertEqual(MuxaConfig.parse("agent_resume = off").agentResume, .off)
        XCTAssertEqual(MuxaConfig.parse("agent_resume = bogus").agentResume, .manual) // 기본
    }

    func testExpandingPaths() {
        let c = MuxaConfig.parse("default_workspace_path = ~/proj").expandingPaths(home: "/Users/x")
        XCTAssertEqual(c.defaultWorkspacePath, "/Users/x/proj")
        let bare = MuxaConfig.parse("default_workspace_path = ~").expandingPaths(home: "/Users/x")
        XCTAssertEqual(bare.defaultWorkspacePath, "/Users/x")
    }
}
