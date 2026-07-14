import SwiftUI

/// 상단바 브레드크럼 — "지금 어디에 있나"만 말하는 **라벨**이다(버튼 아님).
/// 프로젝트 전환의 유일한 경로는 사이드바 트리다. 여기에 클릭·hover 배경을 주면 전환 경로가 둘이 되고,
/// 둘 중 어느 쪽이 진짜인지 사용자가 매번 고민하게 된다.
struct Breadcrumb: View {
    let workspace: Workspace
    /// 표시할 프로젝트. 분리 창은 **그 창의** 프로젝트를 말해야 한다 — 워크스페이스의 활성 프로젝트는
    /// 메인 창의 좌표라 다른 것을 가리킨다. 생략하면 메인의 좌표(활성 프로젝트)를 쓴다.
    var project: Project?

    private var shown: Project? { project ?? workspace.activeProject }

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Text(workspace.name)
                .font(.muxa(.body))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
            // 구분자는 색이 아니라 **크기**로 약해진다(임의 opacity 곱 금지).
            Image(systemName: "chevron.right")
                .font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
            if let project = shown {
                Image(systemName: project.path == nil ? "folder" : "arrow.triangle.branch")
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                // 워크트리 프로젝트의 이름은 브랜치 = 식별자다 → 모노스페이스(사이드바 행과 같은 규칙).
                Text(project.name)
                    .font(project.path == nil ? .muxa(.body, weight: .medium)
                                              : .muxaMono(.body, weight: .medium))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .help(displayPath(shown?.path ?? workspace.path, home: SystemPaths.home))
    }
}
