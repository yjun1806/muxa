import XCTest
@testable import muxa

/// settings.json 병합 — 남의 설정 파일을 고치는 코드다. 사용자 훅 보존과 멱등성이 생명이다.
final class ClaudeHookSettingsTests: XCTestCase {
    private let exe = "/Users/x/Library/Application Support/muxa/bin/muxa-notify"

    /// 사용자가 이미 쓰고 있던 훅 — muxa가 절대 건드리면 안 되는 것.
    private var userHook: [String: Any] {
        ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
    }

    private func commands(_ root: [String: Any], event: ClaudeHookEvent) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let entries = hooks[event.rawValue] as? [[String: Any]] else { return [] }
        return entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    func testMergeRegistersEveryEvent() {
        let merged = ClaudeHookSettings.merged(into: [:], executable: exe)
        for event in ClaudeHookEvent.allCases {
            XCTAssertTrue(
                commands(merged, event: event).contains(ClaudeHookSettings.command(for: event, executable: exe)),
                "\(event.rawValue) 훅이 등록되지 않았다"
            )
        }
        XCTAssertTrue(ClaudeHookSettings.isInstalled(in: merged, executable: exe))
    }

    func testMergePreservesUserHooks() {
        let merged = ClaudeHookSettings.merged(into: userHook, executable: exe)
        XCTAssertTrue(commands(merged, event: .stop).contains("say done"), "사용자 훅이 사라졌다")
        XCTAssertEqual(commands(merged, event: .stop).count, 2)
    }

    func testMergePreservesUnrelatedKeys() {
        let root: [String: Any] = ["model": "opus", "permissions": ["allow": ["Bash"]]]
        let merged = ClaudeHookSettings.merged(into: root, executable: exe)
        XCTAssertEqual(merged["model"] as? String, "opus")
        XCTAssertNotNil(merged["permissions"], "hooks 밖의 키를 건드리면 안 된다")
    }

    /// 재설치가 멱등해야 한다 — 앱을 열 때마다 훅이 중복으로 불어나면 안 된다.
    func testMergeIsIdempotent() {
        let once = ClaudeHookSettings.merged(into: [:], executable: exe)
        let twice = ClaudeHookSettings.merged(into: once, executable: exe)
        XCTAssertEqual(commands(twice, event: .stop).count, 1, "재설치가 훅을 중복시켰다")
    }

    /// 앱 경로가 바뀌면 옛 muxa 훅은 지우고 새 경로로 갈아끼운다(찌꺼기 훅이 남으면 조용히 실패한다).
    func testMergeReplacesStaleMuxaPath() {
        let old = ClaudeHookSettings.merged(into: [:], executable: "/old/muxa-notify")
        let new = ClaudeHookSettings.merged(into: old, executable: exe)
        let stop = commands(new, event: .stop)
        XCTAssertEqual(stop.count, 1)
        XCTAssertTrue(stop[0].hasPrefix(exe))
    }

    func testRemoveKeepsUserHooksAndDropsMuxa() {
        let merged = ClaudeHookSettings.merged(into: userHook, executable: exe)
        let removed = ClaudeHookSettings.removed(from: merged)
        XCTAssertEqual(commands(removed, event: .stop), ["say done"], "제거 후 사용자 훅만 남아야 한다")
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: removed, executable: exe))
    }

    /// muxa 훅만 있던 설정은 제거 후 hooks 키까지 사라져야 한다(빈 껍데기를 남기지 않는다).
    func testRemoveDropsEmptyHooksKey() {
        let merged = ClaudeHookSettings.merged(into: [:], executable: exe)
        let removed = ClaudeHookSettings.removed(from: merged)
        XCTAssertNil(removed["hooks"], "빈 hooks 껍데기가 남았다")
    }

    /// 일부 이벤트만 남은 상태는 미설치로 본다 — 재설치로 멱등 복구된다.
    func testPartialInstallIsNotInstalled() {
        var merged = ClaudeHookSettings.merged(into: [:], executable: exe)
        var hooks = merged["hooks"] as! [String: Any]
        hooks.removeValue(forKey: ClaudeHookEvent.stop.rawValue)
        merged["hooks"] = hooks
        XCTAssertFalse(ClaudeHookSettings.isInstalled(in: merged, executable: exe))
    }

    func testPreToolUseGetsWildcardMatcher() {
        XCTAssertEqual(ClaudeHookSettings.matcher(for: .preToolUse), "*")
        XCTAssertEqual(ClaudeHookSettings.matcher(for: .postToolUse), "*")
        XCTAssertNil(ClaudeHookSettings.matcher(for: .stop), "Stop에 matcher는 의미가 없다")
    }
}
