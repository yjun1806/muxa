import SwiftUI

/// 프로젝트·워크스페이스 상태의 표시 규칙 — 색과 점 크기의 단일 출처
/// (`ServiceStatusStyle`와 같은 자리·같은 패턴). 프로젝트 행·워크스페이스 롤업 점·슬림 막대 세 곳이 공유한다.
///
/// **크롬은 무채, 색은 신호다** — 유휴는 크롬색(muted)이고, 색이 붙는 건 "돌고 있다/기다린다"뿐이다.
/// 프로젝트 롤업 상태의 표시 — 이제 **`StatusStyle`의 얇은 어댑터**다(통일 SSOT). 프로젝트 행·롤업 점·
/// 슬림 막대가 공유한다. 값은 `ProjectStatus.tone`을 거쳐 `StatusStyle`에서 온다(통일 이전과 동일).
enum ProjectStatusStyle {
    static func color(_ status: SidebarTree.ProjectStatus) -> Color { StatusStyle.color(status.tone) }
    static func dotSize(_ status: SidebarTree.ProjectStatus) -> CGFloat { StatusStyle.dotSize(status.tone) }
    static func glyph(_ status: SidebarTree.ProjectStatus) -> String { StatusStyle.glyph(status.tone) }
}
