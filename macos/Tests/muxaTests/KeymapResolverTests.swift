import XCTest
import Carbon.HIToolbox
@testable import muxa

/// KeymapResolver 순수 판정 + 재정의 진단 검증. (ARCHITECTURE 7 키 라우팅)
final class KeymapResolverTests: XCTestCase {
    private let r = KeymapResolver.default

    func testDefaultBindingResolves() {
        // ⌘T → 새 터미널
        if case .newTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: [.command])! {} else {
            XCTFail("⌘T가 newTerminal로 안 풀림")
        }
    }

    func testScratchTerminalBinding() {
        // ⌘⌥T → 스크래치 터미널
        if case .newScratchTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t",
                                                flags: [.command, .option])! {} else {
            XCTFail("⌘⌥T가 newScratchTerminal로 안 풀림")
        }
        // ⌘T 회귀 — 여전히 새 터미널(스크래치 아님)
        if case .newTerminal = r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: [.command])! {} else {
            XCTFail("⌘T가 newTerminal로 안 풀림(회귀)")
        }
    }

    func testScratchTerminalNamedOverride() {
        if case .newScratchTerminal = KeymapAction.named("new_scratch_terminal")! {} else {
            XCTFail("new_scratch_terminal 이름이 newScratchTerminal로 안 풀림")
        }
    }

    func testCommandDigitSwitchesWorkspace() {
        if case .switchWorkspace(let n) = r.resolve(keyCode: kVK_ANSI_3, characters: "3", flags: [.command])! {
            XCTAssertEqual(n, 3)
        } else { XCTFail("⌘3이 switchWorkspace로 안 풀림") }
    }

    func testUnmappedReturnsNil() {
        XCTAssertNil(r.resolve(keyCode: kVK_ANSI_Z, characters: "z", flags: [.command])) // ⌘Z 미매핑 → 터미널 통과
        XCTAssertNil(r.resolve(keyCode: kVK_ANSI_T, characters: "t", flags: [])) // 수정자 없음
    }

    func testParseCombo() {
        XCTAssertEqual(KeymapResolver.parseCombo("cmd+shift+e"),
                       KeymapResolver.Binding(keyCode: kVK_ANSI_E, mods: .init(command: true, shift: true)))
        XCTAssertNil(KeymapResolver.parseCombo("cmd+"))          // 키 없음
        XCTAssertNil(KeymapResolver.parseCombo("hyper+z"))       // 미인식 수정자
    }

    func testOverrideRemapsAction() {
        let r2 = KeymapResolver(overrides: ["new_terminal": "cmd+opt+n"])
        if case .newTerminal = r2.resolve(keyCode: kVK_ANSI_N, characters: "n", flags: [.command, .option])! {} else {
            XCTFail("재정의된 ⌘⌥N이 newTerminal로 안 풀림")
        }
        XCTAssertTrue(r2.diagnostics.isEmpty)
    }

    func testDiagnosticUnknownAction() {
        let d = KeymapResolver(overrides: ["zoom": "cmd+z"]).diagnostics
        XCTAssertEqual(d, [.unknownAction(name: "zoom", combo: "cmd+z")])
    }

    func testDiagnosticParseFailed() {
        let d = KeymapResolver(overrides: ["find": "cmd+"]).diagnostics
        XCTAssertEqual(d, [.parseFailed(name: "find", combo: "cmd+")])
    }

    func testDiagnosticReserved() {
        // ⌘K는 예약(빠른 전환기) — 재정의 거부 + 진단
        let d = KeymapResolver(overrides: ["find": "cmd+k"]).diagnostics
        XCTAssertEqual(d, [.reserved(name: "find", combo: "cmd+k")])
    }

    func testDiagnosticConflict() {
        // 두 동작이 같은 조합을 노리면 conflict(정렬된 처리 순서라 결정론적)
        let d = KeymapResolver(overrides: ["find": "cmd+opt+p", "new_terminal": "cmd+opt+p"]).diagnostics
        XCTAssertTrue(d.contains { if case .conflict(let combo, _) = $0 { return combo == "cmd+opt+p" } else { return false } })
    }
}
