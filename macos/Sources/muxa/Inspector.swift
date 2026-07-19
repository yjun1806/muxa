import SwiftUI

/// 우측 인스펙터의 탭 — 탐색기·Git·알림이 **한 슬롯**을 공유한다(하나만 보임, 통일 폭).
/// 설정은 성격이 달라(전역·자주 안 봄) 인스펙터 탭이 아니라 **별도 패널**로 분리했다. 서비스 서랍도 별개.
enum InspectorTab: String, CaseIterable, Identifiable {
    case explorer, git, attention

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer: return "folder"
        case .git: return "arrow.triangle.merge" // Git 섹션 공통 아이콘(브랜치·워크트리 표시와 구분)
        case .attention: return "bell"
        }
    }

    var label: String {
        switch self {
        case .explorer: return "탐색기"
        case .git: return "Git"
        case .attention: return "알림"
        }
    }
}

/// 인스펙터 상단의 탭 스트립 — 세 탭을 **Flex 균등 분할**(각 영역 동일 폭)로 나눈다. 닫기는 상단바 패널 버튼이 한다.
/// 활성 표시는 matchedGeometry로 탭 사이를 미끄러진다(전환감).
struct InspectorTabStrip: View {
    let state: AppState
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(InspectorTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, Space.xs)
        .frame(height: RowHeight.panelHeader)
        .animation(Motion.fast, value: state.inspectorTab)
    }

    private func tabButton(_ tab: InspectorTab) -> some View {
        let active = state.inspectorTab == tab
        let icon = Image(systemName: tab.icon)
            .font(.muxa(.body))
            .overlay(alignment: .topTrailing) { badge(tab) }
        return Button {
            state.selectInspector(tab)
            if tab == .attention, state.showAttention { state.attention.markAllRead() }
        } label: {
            // 폭 반응형 — 세그먼트가 넓으면 아이콘+라벨, 좁아지면 아이콘만(ViewThatFits가 고른다).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xs) {
                    icon
                    Text(tab.label)
                        .font(.muxa(.label, weight: active ? .semibold : .regular))
                        .lineLimit(1)
                }
                icon
            }
            .foregroundStyle(active ? Color.pFg : Color.pMuted)
            .frame(maxWidth: .infinity) // Flex — 각 탭이 동일 폭을 차지한다
            .frame(height: RowHeight.row)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.pBtnActive)
                        .matchedGeometryEffect(id: "activeInspectorTab", in: indicator)
                }
            }
            .contentShape(Rectangle()) // 히트 영역을 세그먼트 전체로 — 클릭 씹힘 방지
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(tab.label)
    }

    /// 알림 탭 점 배지 — 아이콘 밖으로 나가되 클리핑 없는 overlay라 안 잘린다.
    @ViewBuilder
    private func badge(_ tab: InspectorTab) -> some View {
        if tab == .attention, unread > 0 {
            Circle()
                .fill(Color(nsColor: Palette.borderActivity))
                .frame(width: IconSize.dotSmall, height: IconSize.dotSmall)
                .offset(x: IconSize.dotOffset, y: -IconSize.dotOffset)
        }
    }

    private var unread: Int { state.attentionBadgeCount }
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
