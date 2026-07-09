import SwiftUI

/// 활성 워크스페이스의 터미널 탭 바. (DESIGN.md 4.1 — 워크스페이스별 탭)
/// 각 탭 = 분할 트리 하나. ⌘T 새 탭 · ⌘⇧W 닫기(WorkspaceHost에서 처리)와 짝을 이룬다.
struct TabBarView: View {
    let state: AppState

    var body: some View {
        if let ws = state.activeWorkspace {
            HStack(spacing: 4) {
                ForEach(ws.tabs) { tab in
                    tabItem(ws: ws, tab: tab)
                }
                Button {
                    state.addTab(wsId: ws.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pMuted)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .help("새 탭 (⌘T)")
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.pPanel)
        }
    }

    @ViewBuilder
    private func tabItem(ws: Workspace, tab: TermTab) -> some View {
        let active = tab.id == ws.activeTabId
        HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 11))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            if ws.tabs.count > 1 {
                Button {
                    state.closeTab(wsId: ws.id, tabId: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.pMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(active ? Color.pBg : Color.pBtnHover.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color.pBorderFocus : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            state.setActiveTab(wsId: ws.id, tabId: tab.id)
        }
    }
}
