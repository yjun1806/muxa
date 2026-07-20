import SwiftUI

/// 상단바 브레드크럼 — "지금 어디에 있나"만 말하는 **라벨**이다(버튼 아님).
/// 프로젝트 전환의 유일한 경로는 사이드바 트리다. 여기에 클릭·hover 배경을 주면 전환 경로가 둘이 되고,
/// 둘 중 어느 쪽이 진짜인지 사용자가 매번 고민하게 된다.
struct Breadcrumb: View {
    let workspace: Workspace
    /// 표시할 프로젝트. 분리 창은 **그 창의** 프로젝트를 말해야 한다 — 워크스페이스의 활성 프로젝트는
    /// 메인 창의 좌표라 다른 것을 가리킨다. 생략하면 메인의 좌표(활성 프로젝트)를 쓴다.
    var project: Project?
    /// 현재 브랜치(호출부가 `AppState.currentBranch`로 계산해 넘긴다 — 이 뷰는 순수 라벨 유지).
    /// **프로젝트명과 같으면 숨긴다** — 워크트리 프로젝트는 이름 = 브랜치라 중복이다.
    var branch: String?

    private var shown: Project? { project ?? workspace.activeProject }

    var body: some View {
        // firstTextBaseline — body(12)와 label(11) mono 브랜치가 섞여, center 정렬이면 작은 글자가 살짝 떠 보인다.
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(workspace.name)
                .font(.muxa(.body))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
            // 구분자는 색이 아니라 **크기**로 약해진다(임의 opacity 곱 금지).
            Image(systemName: "chevron.right")
                .font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
            if let project = shown {
                MuxaIcon(name: project.path == nil ? "folder" : MuxaSymbol.gitBranch)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                // **표시명 우선** — 사용자가 붙인 이름(예: "메인")을 그대로 보여준다(사이드바 행과 한 규칙).
                // 브랜치는 Git 패널이 맡는다. 워크트리 프로젝트는 이름 = 브랜치라 자연히 브랜치가 뜨고,
                // 모노스페이스로 식별자임을 알린다.
                Text(project.name)
                    .font(project.path == nil ? .muxa(.body, weight: .medium)
                                              : .muxaMono(.body, weight: .medium))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                // 현재 브랜치 — 프로젝트명과 다를 때만(워크트리는 이름 = 브랜치라 중복). 식별자라 모노스페이스,
                // 위치 라벨(이름)보다 한 단계 약하게(muted·label 크기) — "어디"가 주연, 브랜치는 상태다.
                // 글리프 = 모양 채널: 타이포(크기·서체)만으로 가르면 뒤따르는 경로 텍스트의 시작으로 오독될 수 있다
                // (DESIGN 2: 색만으로 구분하지 않는다 — 모양과 함께).
                if let branch, branch != project.name {
                    HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
                        MuxaIcon(name: MuxaSymbol.gitBranch)
                            .font(.muxa(.micro))
                            .foregroundStyle(Color.pMuted)
                        Text(branch)
                            .font(.muxaMono(.label))
                            .foregroundStyle(Color.pMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .fixedSize()
        .help(displayPath(shown?.path ?? workspace.path, home: SystemPaths.home))
    }
}
