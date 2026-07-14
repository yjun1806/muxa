import Foundation

/// 재개 바인딩이 어디서 왔는가 — **신뢰는 출처가 정한다**.
enum ResumeSource: String, Codable {
    /// 에이전트 훅이 자기 `session_id`를 직접 알려줬다 — **사실**. 이 탭의 세션이 무엇인지 확실하다.
    case hook
    /// cwd로 세션 파일을 뒤져 **추측**했다([[ClaudeSessionIndex]]). 대개 맞지만 틀릴 수 있다.
    case scan
}

/// 에이전트 세션 재개 바인딩(순수 값) — 재개 명령을 탭에 묶어 저장·복원한다.
///
/// muxa는 에이전트별 resume 명령을 스스로 만들지 않는다. Claude Code 등의 훅이
/// `muxa notify --resume-command "claude --resume <sessionId>" --agent claude`로 명령 문자열을
/// 통째로 전달하고, muxa는 그 문자열을 tabId에 묶어 영속·복원만 한다.
///
/// 훅이 없을 때만 cwd로 세션을 **추측**한다(scan). 추측은 자동 실행하지 않는다 — §trusted.
///
/// 복원된 바인딩을 실제로 재개 실행하는 것(승인 게이트·재개 UI)은 이 타입의 책임이 아니다.
struct ResumeBinding: Codable, Equatable {
    /// 복원 시 셸에 입력될 재개 명령 전체(예: "claude --resume <sessionId>").
    var command: String
    /// 표시용 에이전트 라벨(claude/codex 등). 옵셔널.
    var agentLabel: String?
    /// 재개를 실행할 작업 디렉터리(옵셔널). 미지정이면 탭의 복원 cwd를 따른다.
    var cwd: String?
    /// 이 바인딩의 출처. 신뢰 판정의 단일 근거다.
    var source: ResumeSource

    /// 자동 실행해도 되는가 — **훅이 확인해 준 것만** 신뢰한다.
    ///
    /// 종전엔 정확히 거꾸로였다: cwd 디렉터리에서 mtime이 가장 최근인 `.jsonl`을 고른 **추측**이 승인
    /// 게이트를 건너뛰고 자동 실행됐고, 훅이 알려준 **사실**은 매번 사용자 확인을 요구했다. 백그라운드의
    /// 다른 claude가 파일을 건드리기만 해도 엉뚱한 세션을 말없이 이어받을 수 있었다.
    /// 추측은 절대 자동 실행하지 않는다 — 배너로 사용자에게 확인받는다.
    var trusted: Bool { source == .hook }

    /// 레거시 줄 프로토콜(`muxa notify --resume-command <cmd>`)로 들어온 재개 명령의 출처 판정(순수).
    ///
    /// 이 명령은 **소켓으로 들어온 외부 입력**이다 — 같은 uid의 아무 프로세스나(악성 postinstall 등)
    /// 임의 셸 명령을 실을 수 있다. `.hook`으로 신뢰하면 승인 게이트를 건너뛰고 셸에 자동 커밋된다
    /// (executeResume이 Enter까지 친다). 그래서 muxa가 **스스로 만드는 고정 꼴**과 같을 때만 신뢰하고,
    /// 아니면 추측(.scan)으로 강등해 배너 확인을 요구한다 — 임의 명령은 자동 실행하지 않는다.
    ///
    /// 정식 자동 재개 경로는 JSON 훅(SessionStart)이다([[ClaudeHookInterpreter]]) — 거긴 session_id를
    /// 검증하고 명령을 직접 조립한다. 이 줄 프로토콜은 하위호환용 폴백일 뿐이다.
    static func hookSource(forExternalCommand command: String) -> ResumeSource {
        isSafeResumeCommand(command) ? .hook : .scan
    }

    /// `<agent> --resume <안전한 세션id>` 꼴인가 — muxa가 조립하는 재개 명령의 유일한 형태(순수).
    /// 토큰 3개, 가운데가 `--resume`, 마지막이 파일·셸 안전 id, 첫 토큰(에이전트명)은 영숫자·`._-`만.
    static func isSafeResumeCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[1] == "--resume",
              ClaudeSessionIndex.isSafeSessionId(parts[2]),
              !parts[0].isEmpty,
              parts[0].range(of: "[^A-Za-z0-9._-]", options: .regularExpression) == nil
        else { return false }
        return true
    }

    init(command: String, agentLabel: String? = nil, cwd: String? = nil, source: ResumeSource) {
        self.command = command
        self.agentLabel = agentLabel
        self.cwd = cwd
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case command, agentLabel, cwd, source
        case trusted // 구 스냅샷 전용(읽기만 한다)
    }

    /// 하위호환: `source`가 없던 구 스냅샷은 옛 `trusted`의 **의미를 뒤집어** 읽는다.
    /// 옛 trusted=true = mtime 스캔(추측) → `.scan` / 옛 trusted=false = 훅 명령(사실) → `.hook`
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        agentLabel = try c.decodeIfPresent(String.self, forKey: .agentLabel)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        if let s = try c.decodeIfPresent(ResumeSource.self, forKey: .source) {
            source = s
        } else {
            let legacyTrusted = try c.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
            source = legacyTrusted ? .scan : .hook
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(command, forKey: .command)
        try c.encodeIfPresent(agentLabel, forKey: .agentLabel)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encode(source, forKey: .source)
    }
}
