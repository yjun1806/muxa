import Foundation

/// Claude Code 훅이 stdin으로 주는 JSON payload에서 muxa가 쓰는 필드만 뽑은 값(순수).
///
/// CLI(`muxa-notify hook --event <E>`)는 payload를 **해석하지 않고 그대로** 소켓에 넘긴다.
/// 파싱·분류는 전부 여기(앱 안)에서 한다 — 훅 스크립트는 사용자 디스크에 박혀 있어서
/// 앱 업데이트로 못 고치기 때문이다. 훅에 로직을 넣으면 그 로직이 영원히 고정된다.
///
/// 스키마는 Anthropic이 언제든 바꿀 수 있는 비공개 계약이다. 모든 필드가 옵셔널이고,
/// 없으면 조용히 nil이 된다 — 파싱 실패로 신호 전체를 버리지 않는다.
struct ClaudeHookPayload: Equatable {
    /// 도구 이름(PreToolUse/PostToolUse) — 예: "Edit", "Bash".
    let toolName: String?
    /// 도구 입력(PreToolUse/PostToolUse) — 도구별 스키마가 달라 문자열 딕셔너리로만 훑는다.
    let toolInput: [String: String]
    /// 세션 transcript(JSONL) 경로 — Stop 훅이 준다. 본문 보강에 쓴다.
    let transcriptPath: String?
    /// Stop 훅이 직접 실어주는 마지막 assistant 메시지(있으면 transcript를 안 읽어도 된다).
    let lastAssistantMessage: String?
    /// 세션 id — 재개 명령(`claude --resume <id>`) 구성용.
    let sessionId: String?
    /// Notification 훅의 종류 — 예: "idle_prompt", "permission_request".
    let notificationType: String?
    /// Notification 훅의 사람이 읽을 메시지.
    let message: String?
    /// 사용자가 ESC로 끊었는가(Stop) — "완료"와 "중단"을 가른다.
    let isInterrupt: Bool
    /// 백그라운드 작업이 **지금 돌고 있는가** — 턴이 끝나도 done이 아니다(cmux `pending`).
    /// 근거는 `background_tasks[].status == "running"` 하나다.
    let hasPendingBackgroundWork: Bool

    /// 필드가 하나도 없는 payload — JSON이 비었거나 깨졌을 때의 폴백.
    /// 이벤트 이름만으로도 상태 전이(Stop→done 등)는 유효하므로 신호를 통째로 버리지 않는다.
    static let empty = ClaudeHookPayload(
        toolName: nil, toolInput: [:], transcriptPath: nil, lastAssistantMessage: nil,
        sessionId: nil, notificationType: nil, message: nil,
        isInterrupt: false, hasPendingBackgroundWork: false
    )

    /// 훅 JSON(Data)을 파싱한다. 최상위가 객체가 아니면 nil.
    /// 필드가 하나도 없어도 빈 payload로 성공시킨다 — 이벤트 이름만으로도 상태 전이는 유효하다.
    static func parse(_ data: Data) -> ClaudeHookPayload? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return ClaudeHookPayload(
            toolName: nonEmptyString(root["tool_name"]),
            toolInput: stringFields(root["tool_input"]),
            transcriptPath: nonEmptyString(root["transcript_path"]),
            lastAssistantMessage: nonEmptyString(root["last_assistant_message"]),
            sessionId: nonEmptyString(root["session_id"]),
            notificationType: nonEmptyString(root["notification_type"]),
            message: nonEmptyString(root["message"]),
            isInterrupt: root["is_interrupt"] as? Bool ?? false,
            hasPendingBackgroundWork: pendingBackgroundWork(root)
        )
    }

    /// 배경 작업 판정 — 스키마가 사라지면 **false로 폴백**한다(pending을 못 읽었다고 완료 알림을
    /// 영구히 막으면 알림이 통째로 죽는다. 오탐 한 번이 무음보다 낫다).
    ///
    /// **`session_crons`는 근거로 쓰지 않는다.** cmux는 그것도 보지만, 그건 "등록된 cron"이지
    /// "지금 도는 작업"이 아니다. cron을 하나라도 걸어둔 사용자는 **매 턴 완료가 보류**되고,
    /// cron 종료를 알리는 훅이 없으니 그 보류는 풀리지 않는다 — 세션 내내 완료 알림이 0건이 된다.
    private static func pendingBackgroundWork(_ root: [String: Any]) -> Bool {
        guard let tasks = root["background_tasks"] as? [[String: Any]] else { return false }
        return tasks.contains { ($0["status"] as? String) == "running" }
    }

    /// 도구 입력에서 문자열 값만 걷어낸다(중첩 객체·배열은 버린다 — 표시에 안 쓴다).
    private static func stringFields(_ raw: Any?) -> [String: String] {
        guard let dict = raw as? [String: Any] else { return [:] }
        return dict.reduce(into: [String: String]()) { out, entry in
            if let s = entry.value as? String, !s.isEmpty { out[entry.key] = s }
        }
    }

    private static func nonEmptyString(_ raw: Any?) -> String? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        return s
    }
}

/// muxa가 구독하는 Claude Code 훅 이벤트 — 와이어에 실리는 이름은 Claude 쪽 이벤트명 그대로다.
/// 모르는 이벤트는 파싱 단계에서 nil이 되어 조용히 버려진다(스키마가 늘어도 안 깨진다).
/// 훅은 **전역** `~/.claude/settings.json`에 등록된다 — muxa 밖의 모든 claude 세션에서도 매번 프로세스가
/// 스폰된다. 그래서 꼭 필요한 이벤트만 구독한다.
///
/// `PostToolUse`는 일부러 뺐다. 진행 표시(무슨 도구를 쓰는가)는 `PreToolUse`만으로 충분하고 — 오히려
/// 도구가 **시작될 때** 떠야 맞다 — 둘 다 구독하면 도구 호출당 프로세스가 두 번 뜬다. 게다가
/// PostToolUse payload에는 `tool_response`(도구 출력 전문)가 실려 소켓 송신 버퍼를 훌쩍 넘긴다.
enum ClaudeHookEvent: String, Equatable, CaseIterable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
}
