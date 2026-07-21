import XCTest
@testable import muxa

/// settings.json의 statusLine 병합 — 사용자 statusLine 보존(래핑)과 멱등성이 생명이다.
final class ClaudeStatusLineSettingsTests: XCTestCase {
    private let command = "if [ -x '/Users/x/Library/Application Support/muxa/bin/muxa-notify' ]; "
        + "then '/Users/x/Library/Application Support/muxa/bin/muxa-notify' statusline; fi"

    private func statusLineCommand(_ root: [String: Any]) -> String? {
        (root["statusLine"] as? [String: Any])?["command"] as? String
    }

    /// statusLine이 없던 설정에 새로 심는다 — displaced 없음.
    func testInstallsFresh() throws {
        let (root, displaced) = try ClaudeStatusLineSettings.merged(into: [:], command: command)
        XCTAssertEqual(statusLineCommand(root), command)
        XCTAssertNil(displaced)
        XCTAssertTrue(ClaudeStatusLineSettings.isInstalled(in: root, command: command))
    }

    /// 사용자 statusLine이 있으면 그 command를 displaced로 돌려주고(래핑 대상) muxa 것으로 교체한다.
    func testDisplacesUserStatusLine() throws {
        let user: [String: Any] = ["statusLine": ["type": "command", "command": "ccstatusline"]]
        let (root, displaced) = try ClaudeStatusLineSettings.merged(into: user, command: command)
        XCTAssertEqual(displaced, "ccstatusline")
        XCTAssertEqual(statusLineCommand(root), command)
    }

    /// 재설치는 멱등 — 이미 muxa 것이면 교체만, displaced 없음(기존 래핑 유지).
    func testReinstallIsIdempotent() throws {
        let (once, _) = try ClaudeStatusLineSettings.merged(into: [:], command: command)
        let (twice, displaced) = try ClaudeStatusLineSettings.merged(into: once, command: command)
        XCTAssertNil(displaced)
        XCTAssertEqual(statusLineCommand(twice), command)
    }

    /// 다른 필드(model·hooks 등)는 건드리지 않는다.
    func testPreservesOtherFields() throws {
        let root: [String: Any] = ["model": "opus", "hooks": ["Stop": [String]()]]
        let (next, _) = try ClaudeStatusLineSettings.merged(into: root, command: command)
        XCTAssertEqual(next["model"] as? String, "opus")
        XCTAssertNotNil(next["hooks"])
    }

    /// muxa statusLine만 제거한다 — 다른 필드는 남는다.
    func testRemovesMuxaStatusLine() throws {
        let (installed, _) = try ClaudeStatusLineSettings.merged(
            into: ["model": "opus"], command: command)
        let removed = try ClaudeStatusLineSettings.removed(from: installed)
        XCTAssertNil(removed["statusLine"])
        XCTAssertEqual(removed["model"] as? String, "opus")
    }

    /// 사용자 statusLine은 제거하지 않는다(muxa 마커가 없으면 보존).
    func testKeepsUserStatusLineOnRemove() throws {
        let user: [String: Any] = ["statusLine": ["type": "command", "command": "ccstatusline"]]
        let removed = try ClaudeStatusLineSettings.removed(from: user)
        XCTAssertEqual(statusLineCommand(removed), "ccstatusline")
    }

    /// statusLine이 객체가 아니면(모르는 구조) 던진다 — 덮어쓰지 않는다.
    func testThrowsOnUnexpectedShape() {
        let bad: [String: Any] = ["statusLine": "just a string"]
        XCTAssertThrowsError(try ClaudeStatusLineSettings.merged(into: bad, command: command))
        XCTAssertThrowsError(try ClaudeStatusLineSettings.removed(from: bad))
    }
}
