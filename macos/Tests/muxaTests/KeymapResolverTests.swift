import Testing
import Carbon.HIToolbox
@testable import muxa

/// KeymapResolver 순수 판정 + 재정의 진단 검증. (ARCHITECTURE 7 키 라우팅)
struct KeymapResolverTests {
    private let r = KeymapResolver.default

    @Test func testDefaultBindingResolves() {
        // ⌘T → 새 터미널
        if case .newTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: [.command])! {} else {
            Issue.record("⌘T가 newTerminal로 안 풀림")
        }
    }

    @Test func testScratchTerminalBinding() {
        // ⌘⌥T → 스크래치 터미널
        if case .newScratchTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t",
                                                flags: [.command, .option])! {} else {
            Issue.record("⌘⌥T가 newScratchTerminal로 안 풀림")
        }
        // ⌘T 회귀 — 여전히 새 터미널(스크래치 아님)
        if case .newTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: [.command])! {} else {
            Issue.record("⌘T가 newTerminal로 안 풀림(회귀)")
        }
    }

    @Test func testScratchTerminalNamedOverride() {
        if case .newScratchTerminal = KeymapAction.named("new_scratch_terminal")! {} else {
            Issue.record("new_scratch_terminal 이름이 newScratchTerminal로 안 풀림")
        }
    }

    @Test func testCommandDigitSwitchesWorkspace() {
        if case .switchWorkspace(let n) = r.resolve(keyCode: kVK_ANSI_3, characters: "3", flags: [.command])! {
            #expect(n == 3)
        } else { Issue.record("⌘3이 switchWorkspace로 안 풀림") }
    }

    @Test func testUnmappedReturnsNil() {
        #expect(r.resolve(keyCode: kVK_ANSI_Z, characters: "z", flags: [.command]) == nil) // ⌘Z 미매핑 → 터미널 통과
        #expect(r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: []) == nil) // 수정자 없음
    }

    @Test func testParseCombo() {
        #expect(KeymapResolver.parseCombo("cmd+shift+e") == KeymapResolver.Binding(keyCode: kVK_ANSI_E, mods: .init(command: true, shift: true)))
        #expect(KeymapResolver.parseCombo("cmd+") == nil)          // 키 없음
        #expect(KeymapResolver.parseCombo("hyper+z") == nil)       // 미인식 수정자
    }

    @Test func testOverrideRemapsAction() {
        let r2 = KeymapResolver(overrides: ["new_terminal": "cmd+opt+n"])
        if case .newTerminal = r2.resolve(keyCode: kVK_ANSI_N, characters: "n", flags: [.command, .option])! {} else {
            Issue.record("재정의된 ⌘⌥N이 newTerminal로 안 풀림")
        }
        #expect(r2.diagnostics.isEmpty)
    }

    @Test func testDiagnosticUnknownAction() {
        let d = KeymapResolver(overrides: ["zoom": "cmd+z"]).diagnostics
        #expect(d == [.unknownAction(name: "zoom", combo: "cmd+z")])
    }

    @Test func testDiagnosticParseFailed() {
        let d = KeymapResolver(overrides: ["find": "cmd+"]).diagnostics
        #expect(d == [.parseFailed(name: "find", combo: "cmd+")])
    }

    @Test func testDiagnosticReserved() {
        // ⌘K는 예약(빠른 전환기) — 재정의 거부 + 진단
        let d = KeymapResolver(overrides: ["find": "cmd+k"]).diagnostics
        #expect(d == [.reserved(name: "find", combo: "cmd+k")])
    }

    @Test func testDiagnosticConflict() {
        // 두 동작이 같은 조합을 노리면 conflict(정렬된 처리 순서라 결정론적)
        let d = KeymapResolver(overrides: ["find": "cmd+opt+p", "new_terminal": "cmd+opt+p"]).diagnostics
        #expect(d.contains { if case .conflict(let combo, _) = $0 { return combo == "cmd+opt+p" } else { return false } })
    }
}
