import SwiftUI

/// 좌측 워크스페이스 사이드바. (src/Sidebar.tsx 이식) 4모드: expanded/icon/slim/hover.
/// hover는 마우스를 올리면 잠시 expanded로 펼쳐진다(폭 확장).
struct SidebarSUI: View {
    let state: AppState
    @State private var peeking = false

    private var effectiveMode: SidebarMode {
        (state.sidebarMode == .hover && peeking) ? .expanded : state.sidebarMode
    }

    private var width: CGFloat {
        switch effectiveMode {
        case .expanded: return 208
        case .icon, .hover: return 52
        case .slim: return 14
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(state.workspaces.enumerated()), id: \.element.id) { index, ws in
                item(ws, index: index)
            }
            Spacer()
        }
        .padding(6)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        .onHover { hovering in
            if state.sidebarMode == .hover { peeking = hovering }
        }
    }

    @ViewBuilder
    private func item(_ ws: Workspace, index: Int) -> some View {
        let active = ws.id == state.activeId
        Button {
            state.setActiveId(ws.id)
        } label: {
            HStack(spacing: 6) {
                if effectiveMode == .slim {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(active ? Color.pBorderFocus : Color.pMuted.opacity(0.5))
                        .frame(width: 4, height: 22)
                } else {
                    Text(ws.name.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Color.pFg)
                        .frame(width: 22, height: 22)
                        .background(active ? Color.pBorderFocus : Color.pBtnActive)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if effectiveMode == .expanded {
                    Text(ws.name)
                        .font(.system(size: 13))
                        .foregroundStyle(active ? Color.pFg : Color.pMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if index < 8 {
                        Text("⌘\(index + 1)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.pMuted.opacity(0.7))
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, effectiveMode == .expanded ? 8 : 4)
            .frame(maxWidth: .infinity, alignment: effectiveMode == .expanded ? .leading : .center)
            .background(active ? Color.pBtnActive.opacity(0.6) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ws.path ?? ws.name)
    }
}
