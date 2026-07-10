import Bonsplit
import SwiftUI

/// 워크스페이스 하나를 Bonsplit(탭바 + 분할)으로 렌더한다. 각 탭 = 터미널 하나.
/// muxa의 수동 WorkspaceView/TabBarView/Tree를 대체한다.
struct BonsplitWorkspaceView: View {
    let store: TerminalStore

    var body: some View {
        Group {
            if store.showEmptyState {
                // 프로젝트의 모든 탭이 런타임에 닫혀(exit·⌘W) 살아있는 터미널이 없을 때 — 빈 상태 뷰.
                EmptyProjectView(store: store)
            } else {
                BonsplitView(controller: store.controller) { tab, paneId in
                    tabContent(tab.id, paneId: paneId)
                } emptyPane: { paneId in
                    emptyPane(paneId)
                }
            }
        }
        .onAppear { store.ensureInitialTerminal() }
    }

    /// 탭 내용 — 터미널이거나 diff 뷰어(모달 아님, 이 패인의 탭으로 렌더).
    /// 콘텐츠 위에 활동 플래시 테두리를 얹어, 보이는 칸에서 에이전트 활동(완료·벨·알림)이 나면 그 칸을 짚어준다.
    @ViewBuilder
    private func tabContent(_ tabId: TabID, paneId: PaneID) -> some View {
        paneBody(tabId, paneId: paneId)
            // 활성(포커스) 칸을 청록 테두리로 상시 강조하고 비활성 칸은 살짝 어둡게 — "지금 어느 칸인지" 즉시 짚는다.
            .overlay(FocusBorder(store: store, paneId: paneId))
            // 상시 에이전트 상태 테두리(waiting=주황·done=초록) 위에 순간 활동 플래시를 얹는다.
            .overlay(AgentStateBorder(store: store, tabId: tabId))
            .overlay(ActivityFlashBorder(store: store, tabId: tabId))
            // 복원된 재개 바인딩이 있는 터미널 탭엔 상단에 세션 재개 배너를 얹는다(D2). 바인딩 없으면 아무것도 안 그린다.
            .overlay(alignment: .top) { ResumeOverlay(store: store, tabId: tabId) }
    }

    @ViewBuilder
    private func paneBody(_ tabId: TabID, paneId: PaneID) -> some View {
        switch store.content(for: tabId) {
        case .terminal:
            let term = store.term(for: tabId)
            ZStack(alignment: .topTrailing) {
                TerminalRepresentable(term: term) {
                    store.controller.focusPane(paneId)
                }
                SearchOverlay(term: term) // active일 때만 우상단에 뜬다
            }
        case .group:
            if let state = store.group(for: tabId) {
                TabGroupView(group: state, dir: store.workingDir ?? "") { itemId in
                    store.closeGroupItem(tabId, itemId: itemId)
                }
            }
        }
    }

    /// 분할로 생긴 빈 패인 — 새 터미널을 만든다.
    @ViewBuilder
    private func emptyPane(_ paneId: PaneID) -> some View {
        Button {
            store.newTerminal(inPane: paneId)
        } label: {
            Label("새 터미널", systemImage: "plus")
                .font(.system(size: 13))
                .foregroundStyle(Color.pMuted)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .contentShape(Rectangle())
        .onTapGesture { store.controller.focusPane(paneId) }
    }
}

/// 프로젝트의 모든 탭이 런타임에 닫혀 살아있는 터미널이 없을 때 메인 영역에 뜨는 빈 상태 뷰.
/// 자동으로 새 터미널을 강제 생성하지 않는다(사용자가 의도적으로 다 닫았을 수 있음) — 버튼(⌘T)으로 다시 연다.
/// 앱 최초 실행/복원 시 초기 터미널 보장은 store.ensureInitialTerminal이 그대로 담당한다(이건 런타임에 다 닫은 경우).
private struct EmptyProjectView: View {
    let store: TerminalStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 34))
                .foregroundStyle(Color.pMuted)
            Text("터미널이 없습니다")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.pFg)
            Button {
                store.newTerminal()
            } label: {
                Label("새 터미널", systemImage: "plus")
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.pBtnHover, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.pFg)
            }
            .buttonStyle(.plain)
            Text("⌘T")
                .font(.system(size: 11))
                .foregroundStyle(Color.pMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }
}

/// 활성(포커스) 칸 강조 — Bonsplit의 `focusedPaneId`(@Observable)를 읽어 포커스 전환 시 자동 재렌더된다.
/// 활성 칸엔 청록 테두리, 비활성 칸엔 옅은 어둠을 얹어 "지금 입력이 가는 칸"을 확실히 구분한다.
/// 분할이 하나면 늘 활성이라 dim 없이 테두리만(무해). 상태/활동 테두리와 배타적: 활성 칸은 그 칸을 봤다는 뜻이라
/// 에이전트 상태 테두리(waiting/done)가 해제되므로 청록·주황이 겹치지 않는다.
private struct FocusBorder: View {
    let store: TerminalStore
    let paneId: PaneID

    var body: some View {
        let focused = store.controller.focusedPaneId == paneId
        ZStack {
            // 비활성 칸은 살짝 어둡게 — 활성 칸이 도드라진다(터미널 가독성 유지를 위해 옅게).
            Rectangle().fill(.black).opacity(focused ? 0 : 0.16)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.pBorderFocus, lineWidth: 3)
                .opacity(focused ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: focused)
        .allowsHitTesting(false)
    }
}

/// 칸 콘텐츠 위에 얹는 상시 에이전트 상태 테두리(DESIGN 4.5) — store.agentActivity를 관측해 독립 갱신한다.
/// 순간 이벤트(플래시)와 달리 "지금 이 칸의 추정 상태"를 지속 표시한다: waiting=주황(나를 기다림)·done=초록(완료).
/// working·idle은 borderColor가 nil이라 상시 테두리를 그리지 않는다(작업 중엔 조용히). 사용자가 그 칸을 보면 해제된다.
private struct AgentStateBorder: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        let color = store.agentActivity(for: tabId).borderColor
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(color.map { Color(nsColor: $0) } ?? .clear, lineWidth: 2)
            .opacity(color == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: color != nil)
            .allowsHitTesting(false)
    }
}

/// 칸 콘텐츠 위에 얹는 활동 플래시 테두리 — store.flashingTabs를 관측해 독립적으로 갱신한다(콘텐츠 뷰가 keepAllAlive로
/// 유지돼도 이 뷰만 상태 변화에 재렌더). 활동 시 잠깐 켰다가 페이드아웃. focus(청록)와 구분되는 주황(주의 환기색).
private struct ActivityFlashBorder: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        let active = store.flashingTabs.contains(tabId)
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.pBorderActivity, lineWidth: 2)
            .opacity(active ? 1 : 0)
            // 켤 땐 빠르게(주의 환기), 끌 땐 천천히 페이드.
            .animation(.easeOut(duration: active ? 0.12 : 0.5), value: active)
            .allowsHitTesting(false)
    }
}
