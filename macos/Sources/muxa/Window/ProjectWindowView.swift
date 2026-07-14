import SwiftUI

/// 분리 창의 루트 — 프로젝트 하나(그 창이 소유한)를 그린다.
///
/// **사이드바가 없다.** 트리가 둘이면 "프로젝트 전환의 유일한 경로는 사이드바"라는 규칙이 깨지고,
/// 사용자는 두 트리 중 어느 쪽이 진짜인지 매번 고민하게 된다(DESIGN 5). 분리 창은 보던 것을
/// 계속 보는 창이지 탐색하는 창이 아니다 — 전환·추가·⌘K는 메인 창에 남는다.
///
/// 크롬 토글(익스플로러·Git) 값은 **이 창의 `ProjectWindow`**가 소유한다(명세 §6의 비대칭).
struct ProjectWindowView: View {
    let state: AppState
    let windowId: WindowID
    let home: String

    /// 이 창의 모델. reconcile 직전 한 프레임 동안 nil일 수 있다(곧 창이 닫힌다 — I5).
    private var model: ProjectWindow? {
        state.projectWindows.first { $0.id == windowId }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let model, let projectId = model.activeProjectId,
               let located = state.located(projectId) {
                topBar(workspace: located.workspace, project: located.project)
                contentCard(model, workspace: located.workspace, project: located.project)
            } else {
                Color.pPanel
            }
        }
        .background(Color.pPanel)
    }

    /// 상단바 — 신호등 여백 + 브레드크럼 + 합치기 + 패널 토글. 메인의 상단바와 같은 줄 높이를 쓴다
    /// (신호등을 이 높이의 중앙으로 내리는 건 MuxaWindowController).
    private func topBar(workspace: Workspace, project: Project) -> some View {
        HStack(alignment: .center, spacing: Space.md) {
            Color.clear.frame(width: TrafficLights.reservedLeadingWidth)
            Breadcrumb(workspace: workspace, project: project)
            Spacer(minLength: Space.lg)
            IconButton(icon: "macwindow.badge.minus", scale: .body,
                       help: "메인 창으로 합치기") { state.rejoin(windowId) }
            PanelToggle(icon: "folder", on: model?.showExplorer ?? false, help: "파일 익스플로러") {
                state.updateWindow(windowId) { w in
                    var next = w
                    next.showExplorer.toggle()
                    return next
                }
            }
            PanelToggle(icon: "arrow.triangle.branch", on: model?.showGitPanel ?? false, help: "Git 패널") {
                state.updateWindow(windowId) { w in
                    var next = w
                    next.showGitPanel.toggle()
                    return next
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.topBar)
    }

    /// 콘텐츠 카드 — 메인과 같은 층 구조(크롬 위에 카드). 사이드바가 없으니 좌우 여백이 대칭이다.
    private func contentCard(_ model: ProjectWindow,
                             workspace: Workspace, project: Project) -> some View {
        let store = state.store(for: project, in: workspace)
        let dir = project.path ?? workspace.path
        return HStack(spacing: 0) {
            BonsplitWorkspaceView(store: store, windowId: windowId.rawValue)
                .id(project.id)
            if model.showExplorer {
                ResizablePanel(width: explorerWidth(model), range: AppState.panelWidthRange) { w in
                    setWidth(w, explorer: true)
                } content: {
                    FileExplorerPanel(
                        root: dir,
                        revealPath: store.lastOpenedFilePath,
                        revealSeq: store.revealSeq,
                        onOpenFile: { store.openFile($0) },
                        onOpenTerminal: { state.addProject(name: basename($0), path: $0) }
                    )
                }
            }
            if model.showGitPanel {
                ResizablePanel(width: gitPanelWidth(model), range: AppState.gitPanelWidthRange) { w in
                    setWidth(w, explorer: false)
                } content: {
                    GitPanel(
                        dir: dir,
                        sessionBase: project.sessionBaseHead,
                        onResetBaseline: { state.resetSessionBaseline(projectId: project.id, cwd: dir) },
                        onSendReview: { store.injectToTerminal($0) }
                    ) { store.openDiff($0) }
                }
            }
        }
        .contentCard(radius: Radius.lg, border: Color.pBorder)
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.xs)
    }

    // 폭은 창마다 따로 기억한다(저장분이 없으면 앱 기본값 — 메인과 같은 상한/하한을 쓴다).
    private func explorerWidth(_ model: ProjectWindow) -> CGFloat {
        guard let width = model.explorerWidth else { return AppState.defaultPanelWidth }
        return AppState.clampPanelWidth(CGFloat(width))
    }

    private func gitPanelWidth(_ model: ProjectWindow) -> CGFloat {
        guard let width = model.gitPanelWidth else { return AppState.defaultGitPanelWidth }
        return AppState.clampGitPanelWidth(CGFloat(width))
    }

    private func setWidth(_ width: CGFloat, explorer: Bool) {
        state.updateWindow(windowId) { w in
            var next = w
            if explorer {
                next.explorerWidth = Double(AppState.clampPanelWidth(width))
            } else {
                next.gitPanelWidth = Double(AppState.clampGitPanelWidth(width))
            }
            return next
        }
    }
}
