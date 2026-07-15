import SwiftUI

/// 프로젝트·워크스페이스 상태의 표시 규칙 — 색과 점 크기의 단일 출처
/// (`ServiceStatusStyle`와 같은 자리·같은 패턴). 프로젝트 행·워크스페이스 롤업 점·슬림 막대 세 곳이 공유한다.
///
/// **크롬은 무채, 색은 신호다** — 유휴는 크롬색(muted)이고, 색이 붙는 건 "돌고 있다/기다린다"뿐이다.
enum ProjectStatusStyle {
    static func color(_ status: SidebarTree.ProjectStatus) -> Color {
        switch status {
        case .idle: return .pMuted            // 조용함
        case .working: return .pBrand         // 딥틸 — "돌고 있다"
        case .attention: return .pBorderActivity // 호박 — "나를 기다린다"
        }
    }

    /// 유휴는 작게, 신호는 크게 — **색맹 안전**(색보다 크기가 먼저 읽힌다). 접힌 그룹 롤업 점·슬림 막대가 쓴다.
    static func dotSize(_ status: SidebarTree.ProjectStatus) -> CGFloat {
        status == .idle ? IconSize.dotSmall : IconSize.dot
    }

    /// 프로젝트 행의 상태 **아이콘**(펼친 트리) — 색만이 아니라 **모양**으로 상태를 말한다(색맹 안전).
    /// 어휘는 `ServiceStatusStyle.glyph`와 한 계열: 빈 링=조용함, 채운 원=돌고 있음, 느낌표=나를 기다림.
    static func glyph(_ status: SidebarTree.ProjectStatus) -> String {
        switch status {
        case .idle: return "circle"                       // 빈 링 — 조용하다
        case .working: return "circle.fill"               // 채운 원 — 돌고 있다
        case .attention: return "exclamationmark.circle.fill" // 느낌표 — 나를 기다린다
        }
    }
}
