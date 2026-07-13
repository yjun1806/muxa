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
    /// 완료를 보류했다(pending 또는 서브에이전트 때문). 해소되면 그때 done을 낸다.
    var deferredDone = false

    /// 아직 뭔가 돌고 있는가 — 완료 판정의 단일 기준.
    var isBusy: Bool { pendingBackgroundWork || liveSubagents > 0 }
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
    /// 세션 재개 바인딩(SessionStart에서만).
    var resume: ResumeBinding?
    /// 본문이 비어 transcript 꼬리에서 마지막 assistant 메시지를 보강해야 하는 경로.
    var transcriptPath: String?
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
            var out = HookOutcome()
            if let sessionId = payload.sessionId {
                out.resume = ResumeBinding(command: "claude --resume \(sessionId)", agentLabel: "claude", source: .hook)
            }
            return (out, next)

        case .userPromptSubmit:
            // 새 턴 시작 — 이전 턴의 보류·배경작업·서브에이전트 잔여를 전부 리셋한다.
            next = HookSessionState()
            return (HookOutcome(state: .working, clearsDetail: true), next)

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

        case .postToolUse:
            return (HookOutcome(state: .working,
                                detail: ToolActivity.describe(toolName: payload.toolName, input: payload.toolInput)),
                    next)

        case .subagentStart:
            next.liveSubagents += 1
            return (HookOutcome(state: .working), next)

        case .subagentStop:
            next.liveSubagents = max(0, next.liveSubagents - 1)
            // 리드는 이미 끝났는데 서브에이전트를 기다리던 중이었다면, 마지막 하나가 끝나는 지금이 진짜 완료다.
            guard next.deferredDone, !next.isBusy else { return (HookOutcome(), next) }
            next.deferredDone = false
            return (doneOutcome(payload: payload), next)

        case .stop:
            next.pendingBackgroundWork = payload.hasPendingBackgroundWork
            // 배경 작업이나 서브에이전트가 남았으면 턴이 끝나도 완료가 아니다.
            // (사이드바에 ✅가 뜨는데 백그라운드 리뷰 루프가 도는 상황을 막는다.)
            guard !next.isBusy else {
                next.deferredDone = true
                return (HookOutcome(state: .working), next)
            }
            next.deferredDone = false
            return (doneOutcome(payload: payload), next)

        case .notification:
            let isIdle = payload.notificationType == idleNotificationType
            // 유휴 리마인더인데 배경 작업이 돌고 있으면 침묵한다 — idle_prompt payload에는
            // background_tasks가 없으므로 Stop에서 캐시한 값이 유일한 근거다.
            if isIdle && next.pendingBackgroundWork { return (HookOutcome(), next) }
            let category: NotifyCategory = isIdle ? .idleReminder : .needsPermission
            return (HookOutcome(state: .waiting, category: category,
                                title: isIdle ? "유휴" : "입력 대기",
                                body: clamp(payload.message ?? "에이전트가 기다린다")), next)
        }
    }

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
}
