import Bonsplit
import SwiftUI

/// 워크스페이스 하나를 Bonsplit(탭바 + 분할)으로 렌더한다. 각 탭 = 터미널 하나.
/// muxa의 수동 WorkspaceView/TabBarView/Tree를 대체한다.
struct BonsplitWorkspaceView: View {
    let store: TerminalStore

    var body: some View {
        BonsplitView(controller: store.controller) { tab, paneId in
            let term = store.term(for: tab.id)
            ZStack(alignment: .topTrailing) {
                TerminalRepresentable(term: term) {
                    store.controller.focusPane(paneId)
                }
                SearchOverlay(term: term) // active일 때만 우상단에 뜬다
            }
        } emptyPane: { paneId in
            emptyPane(paneId)
        }
        .onAppear { store.ensureInitialTerminal() }
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
