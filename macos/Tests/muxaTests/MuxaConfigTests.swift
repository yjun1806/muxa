import Testing
@testable import muxa

/// MuxaConfig 순수 파서 검증 — 설정 표면의 단일 진실 원천.
struct MuxaConfigTests {
    @Test func testEmptyIsDefaults() {
        #expect(MuxaConfig.parse("") == MuxaConfig.defaults)
    }

    @Test func testParsePairsSkipsCommentsBlanksAndNoEquals() {
        let pairs = MuxaConfig.parsePairs("""
        # comment
        confirm_quit = false

        no equals here
        command_finished_threshold_sec = 3
        """)
        #expect(pairs["confirm_quit"] == "false")
        #expect(pairs["command_finished_threshold_sec"] == "3")
        #expect(pairs["no equals here"] == nil)
        #expect(pairs["# comment"] == nil)
    }

    @Test func testParsePairsLastWins() {
        #expect(MuxaConfig.parsePairs("k = 1\nk = 2")["k"] == "2")
    }

    @Test func testBoolLenientParsing() {
        for on in ["true", "yes", "on", "1"] {
            #expect(!(MuxaConfig.parse("confirm_quit = \(on)").confirmQuit == false), "\(on) → true")
        }
        for off in ["false", "no", "off", "0"] {
            #expect(!(MuxaConfig.parse("confirm_quit = \(off)").confirmQuit), "\(off) → false")
        }
        // 인식 못 하는 값 → 기본값(true) 유지
        #expect(MuxaConfig.parse("confirm_quit = maybe").confirmQuit)
    }

    @Test func testThresholdParsingAndNsConversion() {
        #expect(MuxaConfig.parse("command_finished_threshold_sec = 2.5").commandFinishedThresholdSec == 2.5)
        #expect(MuxaConfig.parse("command_finished_threshold_sec = 2").commandFinishedThresholdNs == 2_000_000_000)
        // 음수는 0으로 클램프
        #expect(MuxaConfig.parse("command_finished_threshold_sec = -5").commandFinishedThresholdNs == 0)
    }

    @Test func testExtractKeybindings() {
        let kb = MuxaConfig.parse("keybind.new_terminal = cmd+t\nkeybind. = ignored\nconfirm_quit = true").keybindings
        #expect(kb["new_terminal"] == "cmd+t")
        #expect(kb[""] == nil)            // 빈 액션 무시
        #expect(kb["confirm_quit"] == nil) // keybind. 접두 아닌 건 제외
    }

    @Test func testAgentResumeParsing() {
        #expect(MuxaConfig.parse("agent_resume = auto").agentResume == .auto)
        #expect(MuxaConfig.parse("agent_resume = off").agentResume == .off)
        #expect(MuxaConfig.parse("agent_resume = bogus").agentResume == .manual) // 기본
    }

    @Test func testExpandingPaths() {
        let c = MuxaConfig.parse("default_workspace_path = ~/proj").expandingPaths(home: "/Users/x")
        #expect(c.defaultWorkspacePath == "/Users/x/proj")
        let bare = MuxaConfig.parse("default_workspace_path = ~").expandingPaths(home: "/Users/x")
        #expect(bare.defaultWorkspacePath == "/Users/x")
    }
}
