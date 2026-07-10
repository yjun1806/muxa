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

/// 복원된 세션의 재개 전략 — 승인 게이트 모드와 직전 종료가 더티(비정상)였는지의 조합으로 결정한다.
/// 뷰(재개 배너)는 이 값 하나만 보고 표시·실행을 정한다(모드·더티 판정을 뷰에 흩뿌리지 않는다).
enum ResumeStrategy: Equatable {
    /// 재개 UI 없음(off). 더티여도 자동 실행하지 않는다 — off의 신뢰 경계가 최우선.
    case none
    /// 사용자 확인 후 재개(평상시 manual). 배너 버튼을 눌러야 실행.
    case manual
    /// 사용자 확인 후 재개 + "비정상 종료 후 복원됨" 강조(manual + 더티). 자동 실행은 안 한다(manual의 신뢰 경계 유지).
    case manualDirty
    /// 복원 후 자동 재개(auto).
    case auto

    /// 이 전략이 복원 후 자동 실행 대상인지 — auto만 true.
    var isAuto: Bool { self == .auto }

    /// 승인 게이트 모드 + 더티 여부 → 재개 전략(순수 판정). 부작용 없음(테스트 가능).
    ///
    /// 더티 종료는 사용자가 의도치 않게 세션을 잃은 상황이라 재개를 조금 더 적극적으로 안내한다.
    /// 단 그 적극성은 "manual일 때 강조 라벨"까지다 — 더티라고 off·manual을 자동 실행으로 승격하지 않는다
    /// (임의 셸 명령 자동 실행은 사용자가 명시적으로 켠 auto에서만 허용, D2 신뢰 경계).
    static func decide(mode: AgentResumeMode, wasDirty: Bool) -> ResumeStrategy {
        switch mode {
        case .off: return .none
        case .auto: return .auto
        case .manual: return wasDirty ? .manualDirty : .manual
        }
    }
}
