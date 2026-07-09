import SwiftUI

/// 좌측 워크스페이스 사이드바. (src/Sidebar.tsx 이식) 4모드: expanded/icon/slim/hover.
/// hover는 마우스를 올리면 잠시 expanded로 펼쳐진다(콘텐츠는 안 밀리도록 오버레이 대신 폭만 확장).
struct SidebarSUI: View {
    let state: AppState
    @State private var peeking = false

    private var effectiveMode: SidebarMode {
        (state.sidebarMode == .hover && peeking) ? .expanded : state.sidebarMode
    }

    private var width: CGFloat {
        switch effectiveMode {
        case .expanded: return 200
        case .icon, .hover: return 52
        case .slim: return 16
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
        .background(Color(nsColor: .windowBackgroundColor))
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
            HStack(spacing: 8) {
                if effectiveMode == .slim {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(active ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 18)
                } else {
                    Text(ws.name.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                if effectiveMode == .expanded {
                    Text(ws.name).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 0)
                    if index < 8 {
                        Text("⌘\(index + 1)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ws.path ?? ws.name)
    }
}
