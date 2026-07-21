import Foundation

/// `~/.claude/settings.json`의 **최상위 `statusLine` 필드**를 muxa sink로 병합/제거하는 **순수** 함수들.
///
/// `hooks`와 스키마가 다르다 — 이벤트별 배열이 아니라 단일 객체 `{type, command}`다. 그래서 별도 타입이지만
/// 규칙은 `ClaudeHookSettings`와 같다:
/// - **사용자 statusLine은 지우지 않는다.** muxa 것(command에 `marker` 포함)만 교체·제거한다.
/// - **재설치는 멱등.** 같은 command를 다시 심어도 불어나지 않는다.
/// - **모르는 구조는 던진다.** `statusLine`이 객체가 아니면 덮어쓰지 않고 `UnexpectedShape`를 던진다.
///
/// 파일 IO·백업·원자적 쓰기, 그리고 밀려난 사용자 command의 **래핑 저장/복원**은 `ClaudeHookInstaller`가 맡는다.
enum ClaudeStatusLineSettings {
    /// muxa sink를 식별하는 표식 — 훅과 **같은 헬퍼**(`muxa-notify`)를 쓰므로 마커도 공유한다.
    static let marker = ClaudeHookSettings.hookMarker

    /// 예상 밖 구조 — 덮어쓰면 사용자 설정이 사라지므로 아무것도 쓰지 않는다.
    struct UnexpectedShape: Error {}

    /// muxa statusLine을 심은 새 root와, 밀려난 **사용자 command**(있으면).
    ///
    /// - 기존이 muxa 것이면 command만 멱등 교체한다(`displaced == nil` — 기존 래핑을 유지).
    /// - 기존이 사용자 것이면 그 command를 `displaced`로 돌려준다 — Installer가 래핑 파일에 저장해
    ///   sink가 pass-through하도록 한다.
    /// - 기존이 없으면 새로 심는다.
    /// - `statusLine`이 객체가 아니면 던진다.
    static func merged(into root: [String: Any], command: String)
        throws -> (root: [String: Any], displaced: String?)
    {
        var displaced: String?
        if let existing = root["statusLine"] {
            guard let object = existing as? [String: Any] else { throw UnexpectedShape() }
            if let current = object["command"] as? String, !current.contains(marker) {
                displaced = current
            }
        }
        var next = root
        next["statusLine"] = ["type": "command", "command": command]
        return (next, displaced)
    }

    /// muxa statusLine만 제거한 새 root(원본 불변). 사용자 것이면 그대로 둔다.
    /// 밀려났던 사용자 command의 **복원**은 Installer가 래핑 파일을 읽어 `merged`로 다시 심는다 —
    /// 여기(순수)는 파일을 모르므로 제거까지만 책임진다.
    static func removed(from root: [String: Any]) throws -> [String: Any] {
        guard let existing = root["statusLine"] else { return root }
        guard let object = existing as? [String: Any] else { throw UnexpectedShape() }
        guard (object["command"] as? String)?.contains(marker) == true else { return root }
        var next = root
        next.removeValue(forKey: "statusLine")
        return next
    }

    /// muxa sink가 이 command로 statusLine에 설치돼 있는가 — 설치 상태 표시용.
    static func isInstalled(in root: [String: Any], command: String) -> Bool {
        guard let object = root["statusLine"] as? [String: Any] else { return false }
        return (object["command"] as? String) == command
    }
}
