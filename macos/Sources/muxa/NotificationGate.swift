import Foundation

/// 훅이 실어 보내는 알림 카테고리 — 배달 긴급도를 가른다(순수 값).
/// muxa notify CLI가 `--category`로 넘기고(문자열), NotifyServer가 파싱해 게이트 입력으로 쓴다.
///
/// Claude Code 훅 프리셋과의 대응(문서용):
/// - `needs-permission` — 권한/입력 대기(PermissionRequest·AskUserQuestion·Notification 훅).
///   안 보이는 칸이면 **항상 시스템 알림**(긴급 — 에이전트가 사용자 없이 못 나아간다).
/// - `turn-complete` — 턴 완료(Stop 훅). 안 보이면 시스템 알림.
/// - `idle-reminder` — 유휴 리마인더(오래 손 안 댄 세션 환기). **조용히** — 팝업 없이 배지만, 억제 가능.
enum NotifyCategory: String, Equatable {
    case needsPermission = "needs-permission"
    case turnComplete = "turn-complete"
    case idleReminder = "idle-reminder"
}

/// 알림 배달 결정(순수 값) — 두 채널을 각각 켤지 끌지.
/// - `badge`: 탭 배지(●) + 프로젝트 알림 + 인박스 이력(자리 비웠다 돌아왔을 때의 복구 동선).
/// - `systemNotification`: macOS 데스크톱 시스템 알림(가장 시끄러운 채널).
///
/// (보이는 칸의 "테두리 플래시" 채널은 제거됐다 — 상태 테두리가 이미 상태를 지속 표시하므로
///  순간 플래시는 중복·소음이었다. 보이는 칸은 그냥 억제한다.)
struct NotificationDelivery: Equatable {
    let badge: Bool
    let systemNotification: Bool

    /// 아무것도 안 함(보이는 칸 — 주의는 이미 사용자에게).
    static let suppressed = NotificationDelivery(badge: false, systemNotification: false)
    /// 배지만(안 보이지만 조용히 — 유휴 리마인더).
    static let badgeOnly = NotificationDelivery(badge: true, systemNotification: false)
    /// 배지 + 시스템 알림(안 보이는 칸의 긴급/완료/자동 신호 — 기존 기본 동작).
    static let badgeAndNotify = NotificationDelivery(badge: true, systemNotification: true)
}

/// 순수 배달 게이트 — 카테고리·가시성으로 배달 방식을 정하는 결정 테이블(부작용 없음, 테스트 가능).
/// muxa "순수 값 타입 분리" 원칙: 판정은 여기서, 실제 발사(부작용)는 TerminalStore가 한다.
///
/// 결정 원칙:
/// - **보이는 칸은 완전 억제**(주의는 이미 사용자에게 — 상태 테두리가 상태를 지속 표시한다).
/// - 안 보이면 카테고리 긴급도로 분기: `needs-permission`·`turn-complete`·`nil`(자동 신호)은
///   배지 + 시스템 알림, `idle-reminder`는 배지만(조용히 — 억제 가능).
///
/// `category == nil`(OSC 9/777 등 자동 신호)은 안 보이면 배지+시스템 알림(기존 동작 보존).
enum NotificationGate {
    static func shouldDeliver(category: NotifyCategory?, isVisibleToUser: Bool) -> NotificationDelivery {
        if isVisibleToUser {
            return .suppressed // 보는 칸은 조용히 — 상태 테두리가 이미 말한다
        }
        switch category {
        case .idleReminder:
            return .badgeOnly
        case .needsPermission, .turnComplete, .none:
            return .badgeAndNotify
        }
    }
}
