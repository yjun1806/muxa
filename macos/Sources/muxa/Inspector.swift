import SwiftUI

/// 우측 인스펙터의 탭 — 탐색기·Git·알림이 **한 슬롯**을 공유한다(하나만 보임, 통일 폭).
/// 설정은 성격이 달라(전역·자주 안 봄) 인스펙터 탭이 아니라 **별도 패널**로 분리했다. 서비스 서랍도 별개.
enum InspectorTab: String, CaseIterable, Identifiable {
    case explorer, git, attention

    var id: String { rawValue }

    // 아이콘·라벨은 진입점인 우측 **액티비티 레일**(`ActivityRail`)이 소유한다 — 탭 스트립이 없어져
    // 여기서 그리지 않는다. 레일은 탐색기·Git·알림에 스크래치·설정까지 5글리프를 한 계열로 통일해 나열한다.
}

/// 인스펙터 본문 — 방문한 탭을 **살려둔다**(keep-alive). 활성 탭만 보이고 나머지는 opacity 0으로 대기해,
/// 전환할 때 재생성 flash·스크롤 손실이 없다(즉시 전환 = 전환감의 핵심).
///
/// 인스펙터가 **닫히면** 이 뷰 자체가 사라져 모든 탭이 해제된다 — 닫힌 동안 숨은 탭의 백그라운드
/// 작업(git 폴링·파일 감시)이 새지 않는다. 살아 있는 건 "열려 있는 동안"뿐.
struct InspectorContent: View {
    let state: AppState
    /// 탐색기·Git이 대상으로 삼을 (ws, project) — 메인 창 소유 활성 프로젝트만. 없으면 그 탭은 빈 상태.
    let target: (ws: Workspace, project: Project)?

    @State private var visited: Set<InspectorTab> = []

    var body: some View {
        let active = state.inspectorTab
        ZStack {
            ForEach(InspectorTab.allCases) { tab in
                if visited.contains(tab) || active == tab {
                    panel(tab)
                        .opacity(active == tab ? 1 : 0)
                        .allowsHitTesting(active == tab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if let active { visited.insert(active) } }
        .onChange(of: state.inspectorTab) { _, tab in if let tab { visited.insert(tab) } }
    }

    @ViewBuilder
    private func panel(_ tab: InspectorTab) -> some View {
        switch tab {
        case .explorer:
            if let t = target {
                let store = state.store(for: t.project, in: t.ws)
                FileExplorerPanel(
                    root: t.project.path ?? t.ws.path,
                    revealPath: store.lastOpenedFilePath,
                    revealSeq: store.revealSeq,
                    onOpenFile: { store.openFile($0) },
                    onOpenTerminal: { dir in state.addProject(name: basename(dir), path: dir) }
                )
            } else {
                emptyProject
            }
        case .git:
            if let t = target {
                let store = state.store(for: t.project, in: t.ws)
                GitPanel(
                    dir: t.project.path ?? t.ws.path,
                    sessionBase: t.project.sessionBaseHead,
                    onResetBaseline: { state.resetSessionBaseline(projectId: t.project.id, cwd: t.project.path ?? t.ws.path) },
                    onSendReview: { store.injectToTerminal($0) },
                    onOpenInViewer: { _ = store.openFile($0) } // 탐색기와 같은 뷰어 경로
                ) { store.openDiff($0) }
            } else {
                emptyProject
            }
        case .attention:
            AttentionInbox(state: state) { state.closeInspector() }
        }
    }

    /// 탐색기·Git 탭인데 대상 프로젝트가 없을 때 — 죽은 화면 대신 무엇을 하면 되는지 안내한다.
    private var emptyProject: some View {
        EmptyState(icon: "square.dashed", title: "열린 프로젝트 없음", compact: true)
    }
}
