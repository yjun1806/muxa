import SwiftUI

/// 상태 톤 → (색·글리프·점크기·라벨)의 **앱 유일 매핑 테이블**(SSOT).
///
/// `ProjectStatusStyle`·`ServiceStatusStyle`은 이 위의 얇은 어댑터로 이행 중이다(단계적 통일).
/// 값은 통일 이전 `ProjectStatusStyle`의 현행 값에 스냅했다 — 그래서 어댑터로 바꿔도 **시각 변화 0**.
///
/// **크롬 무채·색은 신호일 때만**: quiet/inert만 무채(muted), 나머지는 의미색.
/// **색맹 안전**: 톤마다 글리프가 다르다(`StatusStyleTests.글리프는_톤마다_다르다`가 강제).
enum StatusStyle {
    static func glyph(_ tone: StatusTone) -> String {
        switch tone {
        case .quiet: return "circle"                          // 빈 링 — 조용함
        case .active: return "circle.fill"                    // 채운 원 — 돌고 있다
        case .attention: return "ellipsis.circle.fill"        // … — 기다린다(느낌표는 에러처럼 읽혀 뺐다)
        case .success: return "checkmark.circle"              // 체크 — 끝났다
        case .failure: return "exclamationmark.triangle.fill" // 경고 삼각 — 실패(느낌표는 여기에만)
        case .inert: return "circle.dotted"                   // 점선 링 — 아직 안 돎
        }
    }

    static func color(_ tone: StatusTone) -> Color {
        switch tone {
        case .quiet, .inert: return .pMuted          // 무채 — 조용/미실행
        case .active: return .pBrand                 // 딥틸 — 돌고 있다
        case .attention: return .pBorderActivity     // 호박 — 기다린다
        case .success: return .pServiceRunning       // 초록(gitAdded) — 완료/정상
        case .failure: return .pServiceExited        // 빨강 — 실패
        }
    }

    /// 유휴/미실행은 작게, 신호는 크게 — **색보다 크기가 먼저 읽힌다**(색맹 안전).
    static func dotSize(_ tone: StatusTone) -> CGFloat {
        tone == .quiet || tone == .inert ? IconSize.dotSmall : IconSize.dot
    }

    /// VoiceOver·툴팁용 한글 라벨(어휘 단일 출처).
    static func label(_ tone: StatusTone) -> String {
        switch tone {
        case .quiet: return "유휴"
        case .active: return "작업 중"
        case .attention: return "입력 대기"
        case .success: return "완료"
        case .failure: return "비정상 종료"
        case .inert: return "실행 전"
        }
    }
}
