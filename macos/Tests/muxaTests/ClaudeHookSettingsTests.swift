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
        XCTAssertEqual(stop[0], ClaudeHookSettings.command(for: .stop, executable: exe))
        XCTAssertFalse(stop[0].contains("/old/"), "옛 경로 훅이 남았다")
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

    /// 예전 방식(install-integration.sh가 심던 `muxa-notify --state done`)이 남아 있으면 Stop 한 번에
    /// 알림이 두 번 울린다. 형식이 달라도 muxa-notify를 부르는 훅은 전부 새 형식으로 갈아끼워야 한다.
    func testMergeReplacesLegacyStateStyleHooks() {
        let legacy: [String: Any] = ["hooks": [
            "Stop": [["hooks": [["type": "command", "command": "muxa-notify --state done --category turn-complete"]]]],
            "Notification": [["hooks": [["type": "command", "command": "muxa-notify --state waiting"]]]],
        ]]
        let merged = ClaudeHookSettings.merged(into: legacy, executable: exe)
        let stop = commands(merged, event: .stop)
        XCTAssertEqual(stop.count, 1, "레거시 훅이 남아 이중 발화한다")
        XCTAssertFalse(stop[0].contains("--state"), "레거시 형식이 남았다")
        XCTAssertEqual(commands(merged, event: .notification).filter { $0.contains("--state") }.count, 0)
    }

    /// Claude Code는 command를 `/bin/sh -c`로 실행한다. 안정 경로에는 공백이 있으므로
    /// (`~/Library/Application Support/…`) 따옴표가 없으면 sh가 경로를 잘라 읽고 훅이 통째로 죽는다.
    /// 그리고 muxa를 지웠을 때 모든 claude 세션이 sh 에러를 뱉지 않도록 존재 가드로 감싼다.
    func testCommandQuotesPathAndGuardsExistence() {
        let command = ClaudeHookSettings.command(for: .stop, executable: exe)
        XCTAssertEqual(command, "if [ -x '\(exe)' ]; then '\(exe)' hook --event Stop; fi")
        XCTAssertFalse(command.contains("\(exe) hook"), "인용되지 않은 경로가 남았다")
    }

    /// 생성한 command가 실제 POSIX 셸에서 문법 오류 없이 파싱되는가(이 버그의 본질은 셸 문법이었다).
    func testCommandIsValidShellSyntax() throws {
        for event in ClaudeHookEvent.allCases {
            let command = ClaudeHookSettings.command(for: event, executable: "/tmp/muxa test/muxa-notify")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-n", "-c", command] // -n = 문법 검사만(실행 안 함)
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "셸 문법 오류: \(command)")
        }
    }

    /// 경로에 작은따옴표가 있어도 셸 문법이 깨지지 않는다.
    func testCommandEscapesSingleQuoteInPath() {
        let quoted = ClaudeHookSettings.shellQuoted("/Users/o'brien/bin/muxa-notify")
        XCTAssertEqual(quoted, "'/Users/o'\\''brien/bin/muxa-notify'")
    }

    /// 인용된 command도 설치 감지에 잡혀야 한다(멱등 재설치가 깨지지 않게).
    func testQuotedCommandIsDetectedAsInstalled() {
        let merged = ClaudeHookSettings.merged(into: [:], executable: exe)
        XCTAssertTrue(ClaudeHookSettings.isInstalled(in: merged, executable: exe))
    }

    /// 따옴표 없이 깨져 설치됐던 훅(이 버그의 산물)도 재설치가 멱등하게 교체한다.
    func testMergeReplacesUnquotedBrokenHooks() {
        let broken: [String: Any] = ["hooks": [
            "Stop": [["hooks": [["type": "command", "command": "\(exe) hook --event Stop"]]]],
        ]]
        let merged = ClaudeHookSettings.merged(into: broken, executable: exe)
        let stop = commands(merged, event: .stop)
        XCTAssertEqual(stop.count, 1, "깨진 훅이 남아 중복됐다")
        XCTAssertEqual(stop[0], ClaudeHookSettings.command(for: .stop, executable: exe),
                       "인용·가드가 붙은 새 형식으로 교체되지 않았다")
    }

    func testPreToolUseGetsWildcardMatcher() {
        XCTAssertEqual(ClaudeHookSettings.matcher(for: .preToolUse), "*")
        XCTAssertEqual(ClaudeHookSettings.matcher(for: .postToolUse), "*")
        XCTAssertNil(ClaudeHookSettings.matcher(for: .stop), "Stop에 matcher는 의미가 없다")
    }
}
