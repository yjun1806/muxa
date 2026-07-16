import SwiftUI

/// 상태 톤 → (색·글리프·점크기·라벨)의 **앱 유일 매핑 테이블**(SSOT).
///
/// 이것은 **에이전트/프로젝트 축**의 SSOT다. `ProjectStatusStyle`은 이 위의 얇은 어댑터다(`.tone` 경유, 통일 완료).
/// **서비스는 별개 축이라 여기 접지 않는다** — 서비스 실행중(파랑 ▶)·정상종료(무채 ■)는 에이전트 작업중(틸 ●)·
/// 완료(초록 ✓)와 **일부러 색·모양이 다르다**(한 행에 나란히 떠도 안 헷갈리게, 두 축 모델). 서비스 표시는
/// `ServiceStatusStyle`이 독립 SSOT로 맡는다(통일 대상 아님 — 합치면 두 축 구분이 사라진다).
///
/// **크롬 무채·색은 신호일 때만**: quiet/inert만 무채(muted), 나머지는 의미색.
/// **색맹 안전**: 톤마다 글리프가 다르다(`StatusStyleTests.글리프는_톤마다_다르다`가 강제).
enum StatusStyle {
    static func glyph(_ tone: StatusTone) -> String {
        switch tone {
        case .quiet: return "circle"                          // 빈 링 — 조용함
        case .active: return "circle.fill"                    // 채운 원 — 돌고 있다
        case .attention: return "pause.fill"                  // ⏸ 정지 바 — 기다린다(최종안 C, 느낌표·… 아님)
        case .success: return "checkmark.circle"              // 체크 — 끝났다
        case .failure: return "exclamationmark.triangle.fill" // 경고 삼각 — 실패(느낌표는 여기에만)
        case .inert: return "circle.dotted"                   // 점선 링 — 아직 안 돎
        }
    }

    static func color(_ tone: StatusTone) -> Color {
        switch tone {
        case .quiet, .inert: return .pMuted          // 무채 — 조용/미실행
        case .active: return .pWork                  // 인디고 — 돌고 있다(스피너)
        case .attention: return .pWaiting            // 로즈 — 기다린다(펄스, 앰버 아님)
        case .success: return .pDone                 // 세이지 — 끝났다(git 초록과 분리)
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
