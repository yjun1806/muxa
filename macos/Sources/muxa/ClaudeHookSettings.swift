import Foundation

/// `~/.claude/settings.json`의 `hooks` 블록을 muxa 훅으로 병합/제거하는 **순수** 함수들.
///
/// 남의 설정 파일을 앱이 고치는 일이라 규칙을 엄격히 둔다:
/// - **사용자 훅은 절대 건드리지 않는다.** muxa가 넣은 항목(`hookMarker`를 포함한 command)만
///   지우고 다시 넣는다. 재설치가 멱등이어야 설정이 중복으로 불어나지 않는다.
/// - **모르는 키는 그대로 보존한다.** hooks 밖의 필드(permissions·model·env…)는 손대지 않는다.
/// - 파일 IO는 여기 없다 — `ClaudeHookInstaller`가 맡는다(원자적 쓰기·백업).
enum ClaudeHookSettings {
    /// muxa가 심은 훅을 식별하는 표식. 이 문자열이 command에 있으면 muxa 소유로 본다.
    static let hookMarker = "muxa-notify hook"

    /// 이벤트별 matcher — PreToolUse/PostToolUse만 도구 matcher가 의미가 있다(전체 = "*").
    /// 나머지 이벤트는 matcher 없이 등록한다.
    static func matcher(for event: ClaudeHookEvent) -> String? {
        switch event {
        case .preToolUse, .postToolUse: return "*"
        default: return nil
        }
    }

    /// 훅 타임아웃(초) — fire-and-forget이라 짧게. CLI가 200ms에 connect를 끊고 exit 0 한다.
    static let timeoutSeconds = 5

    /// muxa 훅을 병합한 새 settings 딕셔너리를 돌려준다(원본 불변).
    /// 이미 muxa 훅이 있으면 먼저 제거하고 다시 넣는다 — 재설치가 멱등이다.
    static func merged(into root: [String: Any], executable: String) -> [String: Any] {
        var next = removed(from: root)
        var hooks = next["hooks"] as? [String: Any] ?? [:]
        for event in ClaudeHookEvent.allCases {
            var entries = hooks[event.rawValue] as? [[String: Any]] ?? []
            entries.append(entry(for: event, executable: executable))
            hooks[event.rawValue] = entries
        }
        next["hooks"] = hooks
        return next
    }

    /// muxa가 넣은 훅만 걷어낸 새 settings 딕셔너리(원본 불변). 사용자 훅은 남는다.
    /// 항목이 비면 이벤트 키를 지우고, hooks 자체가 비면 hooks 키도 지운다(찌꺼기 안 남김).
    static func removed(from root: [String: Any]) -> [String: Any] {
        var next = root
        guard var hooks = next["hooks"] as? [String: Any] else { return next }
        for (event, raw) in hooks {
            guard let entries = raw as? [[String: Any]] else { continue }
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

    /// 훅 명령줄. **셸 스니펫이 아니라 바이너리 직접 실행**이다 — 일부 에이전트 런타임이 command를
    /// 셸 없이 exec해서 인라인 스니펫이 "No such file or directory"로 깨진다(cmux가 codex에서 겪었다).
    /// 경로는 앱 번들 안이 아니라 Application Support의 안정 경로다(앱을 옮겨도 안 깨진다).
    static func command(for event: ClaudeHookEvent, executable: String) -> String {
        "\(executable) hook --event \(event.rawValue)"
    }
}
