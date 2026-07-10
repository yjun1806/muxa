import Bonsplit
import SwiftUI

/// 워크스페이스 하나를 Bonsplit(탭바 + 분할)으로 렌더한다. 각 탭 = 터미널 하나.
/// muxa의 수동 WorkspaceView/TabBarView/Tree를 대체한다.
struct BonsplitWorkspaceView: View {
    let store: TerminalStore

    var body: some View {
        BonsplitView(controller: store.controller) { tab, paneId in
            tabContent(tab.id, paneId: paneId)
        } emptyPane: { paneId in
            emptyPane(paneId)
        }
        .onAppear { store.ensureInitialTerminal() }
    }

    /// 탭 내용 — 터미널이거나 diff 뷰어(모달 아님, 이 패인의 탭으로 렌더).
    /// 콘텐츠 위에 활동 플래시 테두리를 얹어, 보이는 칸에서 에이전트 활동(완료·벨·알림)이 나면 그 칸을 짚어준다.
    @ViewBuilder
    private func tabContent(_ tabId: TabID, paneId: PaneID) -> some View {
        paneBody(tabId, paneId: paneId)
            .overlay(ActivityFlashBorder(store: store, tabId: tabId))
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
