import SwiftUI

/// 좌측 워크스페이스 사이드바. (src/Sidebar.tsx 이식) 4모드: expanded/icon/slim/hover.
/// hover는 마우스를 올리면 잠시 expanded로 펼쳐진다 — 콘텐츠를 밀지 않고 위에 뜬다(오버레이,
/// ContentView가 접힌 폭만 예약). peek 중엔 우측 그림자로 떠 있음을 표시한다.
struct SidebarSUI: View {
    let state: AppState
    @State private var peeking = false
    @State private var hoveredId: String? // 접힌 모드에서 이름 툴팁 표시 대상

    private var effectiveMode: SidebarMode {
        (state.sidebarMode == .hover && peeking) ? .expanded : state.sidebarMode
    }

    private var width: CGFloat { effectiveMode.baseWidth }

    /// 이름이 안 보이는 접힌 모드(아이콘·슬림)에서만 호버 이름 툴팁을 띄운다.
    private var showsNameOnHover: Bool {
        effectiveMode == .icon || effectiveMode == .slim
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
        .overlay(alignment: .trailing) {
            if peeking { Rectangle().fill(Color.pBorder).frame(width: 1) }
        }
        .shadow(color: peeking ? .black.opacity(0.28) : .clear, radius: peeking ? 10 : 0, x: 2)
        .animation(.easeOut(duration: 0.12), value: peeking)
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
        .onHover { hovering in
            guard showsNameOnHover else { return }
            if hovering { hoveredId = ws.id }
            else if hoveredId == ws.id { hoveredId = nil }
        }
        .popover(isPresented: nameTooltip(ws), arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pFg)
                if let path = ws.path {
                    Text(displayPath(path, home: SystemPaths.home))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    /// 접힌 모드에서 이 항목이 호버 중일 때만 이름 팝오버를 연다.
    private func nameTooltip(_ ws: Workspace) -> Binding<Bool> {
        Binding(
            get: { showsNameOnHover && hoveredId == ws.id },
            set: { open in if !open, hoveredId == ws.id { hoveredId = nil } }
        )
    }
}
