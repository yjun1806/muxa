import Foundation

/// 화면에 그릴 수 있는 상태 **톤** — 표시 어휘의 단일 집합(SSOT).
///
/// 도메인 상태(`AgentActivity`(탭)·`SidebarTree.ProjectStatus`(롤업)·`ServiceState`(서비스))는 의미가
/// 서로 달라 **타입을 합치지 않는다**. 대신 "화면에 어떤 톤으로 그릴까"만 이 한 집합으로 모아,
/// 색·글리프·점크기·라벨을 `StatusStyle` 한 곳에서 받는다. 매핑 테이블이 여러 곳에 흩어지지 않게.
///
/// **색맹 안전**: 톤마다 색과 **모양이 둘 다** 달라야 한다(`StatusStyleTests`가 글리프 유일성을 못 박는다).
enum StatusTone: CaseIterable {
    case quiet      // 유휴 — 조용함
    case active     // 돌고 있다(에이전트 작업중·서비스 실행중)
    case attention  // 사람을 기다린다(입력 대기·주의)
    case success    // 끝났다(완료·정상 종료)
    case failure    // 실패(비정상 종료)
    case inert      // 아직 안 돎(실행 전)
}

// MARK: 도메인 상태 → 톤 (매핑 층 — 순수. 이후 단계가 여기서 파생한다)

extension SidebarTree.ProjectStatus {
    /// 프로젝트 롤업 상태의 표시 톤. idle=조용, working=돌고있음, attention=기다림.
    var tone: StatusTone {
        switch self {
        case .idle: return .quiet
        case .working: return .active
        case .attention: return .attention
        }
    }
}

extension AgentActivity {
    /// 탭 하나의 추정 상태 → 표시 톤. 롤업(ProjectStatus)과 같은 어휘를 써 사이드바가 한목소리로 그린다.
    var tone: StatusTone {
        switch self {
        case .idle: return .quiet
        case .working: return .active
        case .waiting: return .attention
        case .done: return .success
        }
    }
}
