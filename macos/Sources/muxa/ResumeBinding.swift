import Foundation

/// 에이전트 세션 재개 바인딩(순수 값) — 훅이 통째로 넘긴 "재개 명령"을 탭에 묶어 저장·복원한다.
///
/// muxa는 에이전트별 resume 명령을 스스로 만들지 않는다. Claude Code 등의 훅이
/// `muxa notify --resume-command "claude --resume <sessionId>" --agent claude`로 명령 문자열을
/// 통째로 전달하고, muxa는 그 문자열을 tabId에 묶어 영속·복원만 한다. 이게 더 단순하고 muxa 범위에 맞다.
///
/// 복원된 바인딩을 실제로 재개 실행하는 것(승인 게이트·재개 UI)은 이 타입의 책임이 아니다 —
/// 복원 시 맵에 담아두기만 하고, 실행은 나중 단계가 담당한다.
struct ResumeBinding: Codable, Equatable {
    /// 복원 시 셸에 입력될 재개 명령 전체(예: "claude --resume <sessionId>").
    var command: String
    /// 표시용 에이전트 라벨(claude/codex 등). 옵셔널.
    var agentLabel: String?
    /// 재개를 실행할 작업 디렉터리(옵셔널). 미지정이면 탭의 복원 cwd를 따른다.
    var cwd: String?

    init(command: String, agentLabel: String? = nil, cwd: String? = nil) {
        self.command = command
        self.agentLabel = agentLabel
        self.cwd = cwd
    }
}
