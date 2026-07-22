import SwiftUI

/// 인앱 브라우저 서브탭 — 풀 크롬(뒤로·앞으로·새로고침 + 주소창 + 시스템 브라우저로 열기) + 페이지.
/// 상태는 BrowserTab이 소유하고, 이 뷰는 controlled로 렌더·명령만 낸다.
struct BrowserView: View {
    @Bindable var tab: BrowserTab
    /// 이 서브탭이 화면에 보이는가 — lazy 로드 게이트로 BrowserWebView에 넘긴다.
    let shouldLoad: Bool

    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HDivider()
            BrowserWebView(tab: tab, shouldLoad: shouldLoad)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.pBg)
    }

    private var toolbar: some View {
        HStack(spacing: Space.sm) {
            navButton("chevron.left", enabled: tab.canGoBack, help: "뒤로") { tab.goBackAction() }
            navButton("chevron.right", enabled: tab.canGoForward, help: "앞으로") { tab.goForwardAction() }
            navButton(tab.isLoading ? "xmark" : "arrow.clockwise", enabled: true,
                      help: tab.isLoading ? "중지" : "새로고침") {
                if tab.isLoading { tab.stopAction() } else { tab.reloadAction() }
            }

            addressField

            navButton("arrow.up.right.square", enabled: true, help: "시스템 브라우저로 열기") {
                NSWorkspace.shared.open(tab.currentURL)
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: RowHeight.header)
        .background(Color.pPanel)
    }

    private var addressField: some View {
        TextField("주소 입력", text: $tab.addressText)
            .textFieldStyle(.plain)
            .font(.muxaMono(.body))
            .foregroundStyle(Color.pFg)
            .lineLimit(1)
            .padding(.horizontal, Space.md)
            .frame(height: RowHeight.toolbar - 4)
            .background(Color.pBg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
            .focused($addressFocused)
            .onChange(of: addressFocused) { _, focused in tab.isEditingAddress = focused }
            .onSubmit { tab.submitAddress() }
    }

    private func navButton(_ icon: String, enabled: Bool, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.muxa(.title))
                .foregroundStyle(enabled ? Color.pFg : Color.pMuted.opacity(0.4))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .clickCursor()
        .help(help)
    }
}
