import Foundation

/// `~/.claude/settings.json`의 `hooks` 블록을 muxa 훅으로 병합/제거하는 **순수** 함수들.
///
/// 남의 설정 파일을 앱이 고치는 일이라 규칙을 엄격히 둔다:
/// - **사용자 훅은 절대 건드리지 않는다.** muxa가 넣은 항목(`hookMarker`를 포함한 command)만
///   지우고 다시 넣는다. 재설치가 멱등이어야 설정이 중복으로 불어나지 않는다.
/// - **모르는 키는 그대로 보존한다.** hooks 밖의 필드(permissions·model·env…)는 손대지 않는다.
/// - 파일 IO는 여기 없다 — `ClaudeHookInstaller`가 맡는다(원자적 쓰기·백업).
enum ClaudeHookSettings {
    /// muxa가 심은 훅을 식별하는 표식. 이 문자열이 command에 있으면 muxa 소유로 보고 제거·교체한다.
    ///
    /// `muxa-notify hook`이 아니라 `muxa-notify`로 넓게 잡는 이유: 예전 방식(`scripts/install-integration.sh`가
    /// 심던 `muxa-notify --state done …`)이 남아 있으면 Stop 한 번에 레거시 알림과 훅 알림이 **두 번** 울린다.
    /// muxa-notify를 부르는 훅은 어느 형식이든 muxa 소유로 보고 새 형식으로 갈아끼운다.
    static let hookMarker = "muxa-notify"

    /// 이벤트별 matcher — 도구 이벤트(PreToolUse)만 matcher가 의미가 있다(전체 = "*").
    /// 나머지 이벤트는 matcher 없이 등록한다.
    static func matcher(for event: ClaudeHookEvent) -> String? {
        event == .preToolUse ? "*" : nil
    }

    /// 훅 타임아웃(초) — fire-and-forget이라 짧게. CLI가 200ms에 connect를 끊고 exit 0 한다.
    static let timeoutSeconds = 5

    /// 예상 밖 구조를 만났다 — 덮어쓰면 사용자 훅이 사라지므로 아무것도 쓰지 않는다.
    struct UnexpectedShape: Error {}

    /// muxa 훅을 병합한 새 settings 딕셔너리를 돌려준다(원본 불변).
    /// 이미 muxa 훅이 있으면 먼저 제거하고 다시 넣는다 — 재설치가 멱등이다.
    ///
    /// **기대한 타입이 아니면 던진다.** `?? [:]`/`?? []`로 삼키면 사용자가 손으로 넣은 구조나
    /// 우리가 모르는 새 스키마를 **통째로 덮어써 지운다** — "사용자 훅은 절대 건드리지 않는다"는
    /// 이 파일의 계약이 거기서 깨진다. 모르면 손대지 않는 게 유일하게 안전한 선택이다.
    static func merged(into root: [String: Any], executable: String) throws -> [String: Any] {
        var next = try removed(from: root) // hooks가 객체가 아니면 여기서 던진다
        var hooks = next["hooks"] as? [String: Any] ?? [:]
        for event in ClaudeHookEvent.allCases {
            var entries: [[String: Any]] = []
            if let existing = hooks[event.rawValue] {
                guard let typed = existing as? [[String: Any]] else { throw UnexpectedShape() }
                entries = typed
            }
            entries.append(entry(for: event, executable: executable))
            hooks[event.rawValue] = entries
        }
        next["hooks"] = hooks
        return next
    }

    /// muxa가 넣은 훅만 걷어낸 새 settings 딕셔너리(원본 불변). 사용자 훅은 남는다.
    /// 항목이 비면 이벤트 키를 지우고, hooks 자체가 비면 hooks 키도 지운다(찌꺼기 안 남김).
    /// hooks가 객체가 아니면 던진다(모르는 구조를 건드리지 않는다).
    static func removed(from root: [String: Any]) throws -> [String: Any] {
        var next = root
        guard let raw = next["hooks"] else { return next }
        guard var hooks = raw as? [String: Any] else { throw UnexpectedShape() }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue } // 모르는 구조는 그대로 보존
            let kept = entries.compactMap(strippingMuxaCommands)
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { next.removeValue(forKey: "hooks") } else { next["hooks"] = hooks }
        return next
    }

    /// 이 앱이 등록한 훅이 **모든 이벤트에** 살아있는가 — 설치 상태 표시용.
    /// 일부만 남은 상태(사용자가 손으로 지웠거나 옛 경로가 박힌 경우)도 "미설치"로 본다 — 재설치하면 멱등하게 복구된다.
    static func isInstalled(in root: [String: Any], executable: String) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return ClaudeHookEvent.allCases.allSatisfy { event in
            guard let entries = hooks[event.rawValue] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let commands = entry["hooks"] as? [[String: Any]] else { return false }
                return commands.contains { ($0["command"] as? String) == command(for: event, executable: executable) }
            }
        }
    }

    /// 한 이벤트 그룹에서 muxa 명령만 제거한다. 그룹이 통째로 비면 nil(그룹 자체를 지운다).
    private static func strippingMuxaCommands(_ entry: [String: Any]) -> [String: Any]? {
        guard let commands = entry["hooks"] as? [[String: Any]] else { return entry }
        let kept = commands.filter { !isMuxaCommand($0) }
        if kept.isEmpty { return nil }
        var next = entry
        next["hooks"] = kept
        return next
    }

    private static func isMuxaCommand(_ command: [String: Any]) -> Bool {
        guard let text = command["command"] as? String else { return false }
        return text.contains(hookMarker)
    }

    /// 한 이벤트의 훅 등록 항목.
    private static func entry(for event: ClaudeHookEvent, executable: String) -> [String: Any] {
        var entry: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": command(for: event, executable: executable),
                "timeout": timeoutSeconds,
            ]]
        ]
        if let matcher = matcher(for: event) { entry["matcher"] = matcher }
        return entry
    }

    /// 훅 명령줄. 경로는 앱 번들 안이 아니라 Application Support의 안정 경로다(앱을 옮겨도 안 깨진다).
    ///
    /// 두 가지를 반드시 지킨다 — 둘 다 실제로 깨져 본 것들이다:
    /// - **경로 인용.** Claude Code는 command를 `/bin/sh -c <command>`로 돌리는데 안정 경로엔 공백이 있다
    ///   (`~/Library/Application Support/…`). 인용이 없으면 sh가 `/Users/…/Library/Application`까지만
    ///   실행 파일로 읽고 "No such file or directory"로 죽는다.
    /// - **존재 가드.** 사용자가 muxa를 지우면 이 훅은 settings.json에 남는다. 가드가 없으면 **모든 claude
    ///   세션이** 매 도구 호출마다 sh 에러를 뱉는다. `if [ -x … ]`로 감싸 없으면 조용히 통과시킨다(exit 0).
    ///   (orca도 자기 훅을 같은 방식으로 감싼다.)
    static func command(for event: ClaudeHookEvent, executable: String) -> String {
        let quoted = shellQuoted(executable)
        return "if [ -x \(quoted) ]; then \(quoted) hook --event \(event.rawValue); fi"
    }

    /// POSIX 셸용 인용 — 작은따옴표로 감싸고, 경로에 작은따옴표가 있으면 `'\''`로 탈출시킨다.
    /// 작은따옴표 안에서는 공백·$·백틱이 전부 리터럴이라 가장 안전하다.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
