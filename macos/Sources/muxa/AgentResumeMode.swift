import Foundation

/// 복원된 에이전트 세션 재개의 승인 게이트 모드(설정 `agent_resume`) — 순수 값 타입. (D2)
///
/// 재개 명령(`ResumeBinding.command`)은 훅이 통째로 넘긴 **임의 셸 명령**이다. 복원 후 이를 자동으로
/// 실행하는 것은 신뢰 경계를 넘는 보안 리스크라, 기본값은 사용자가 직접 눌러야 실행되는 `manual`이다.
/// `auto`는 그 위험을 감수하겠다고 명시적으로 켠 사용자에게만 허용한다.
enum AgentResumeMode: String, Codable, CaseIterable {
    /// 재개 바인딩이 있어도 UI·실행을 하지 않는다(무시).
    case off
    /// 복원된 탭에 재개 버튼을 띄우고, 사용자가 눌러야 실행한다. **기본값**(안전).
    case manual
    /// 복원 후 짧은 지연을 두고 자동 실행한다(사용자가 명시적으로 켠 경우만).
    case auto
}
