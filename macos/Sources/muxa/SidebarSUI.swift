import SwiftUI

/// 좌측 워크스페이스 사이드바. (src/Sidebar.tsx 이식) 4모드: expanded/icon/slim/hover.
/// hover는 마우스를 올리면 잠시 expanded로 펼쳐진다 — 콘텐츠를 밀지 않고 위에 뜬다(오버레이,
/// ContentView가 접힌 폭만 예약). peek 중엔 우측 그림자로 떠 있음을 표시한다.
/// 이름이 안 보이는 모드(icon·slim)는 항목에 마우스를 올리면 우측에 이름 칩이 즉시 뜬다.
struct SidebarSUI: View {
    let state: AppState
    @State private var peeking = false
    /// 지금 마우스가 올라간 워크스페이스 — 항목 강조 + 이름 칩 표시 대상.
    @State private var hoveredId: String?
    /// 우클릭 메뉴가 열려 있는 워크스페이스 — 항목 강조를 유지하고, hover 모드에선 사이드바를 펼친 채로 붙든다
    /// (메뉴는 별도 창이라 마우스가 사이드바를 벗어나므로, 이게 없으면 메뉴만 남고 사이드바가 접힌다).
    @State private var menuOpenId: String?

    private var effectiveMode: SidebarMode {
        (state.sidebarMode == .hover && (peeking || menuOpenId != nil)) ? .expanded : state.sidebarMode
    }

    private var width: CGFloat { effectiveMode.baseWidth }

    /// 이름이 보이지 않는 모드 — 호버 시 이름 칩을 띄운다.
    private var showsNameChip: Bool { effectiveMode != .expanded }

    /// 이름 칩과 사이드바 우측 경계 사이 간격.
    private static let chipGap: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(state.workspaces.enumerated()), id: \.element.id) { index, ws in
                item(ws, index: index)
            }
            Spacer()
        }
        // 슬림(14pt)은 좌우 패딩을 빼야 항목이 사이드바 폭을 다 쓴다 — 안 그러면 클릭 영역이 2pt로 쪼그라들어
        // 좌클릭 전환도, 우클릭 메뉴도 조준이 사실상 불가능해진다(색 막대는 그 영역 밖으로 그려져 멀쩡해 보인다).
        .padding(.vertical, Space.sm)
        .padding(.horizontal, effectiveMode == .slim ? 0 : Space.sm)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        // peek로 펼쳐졌을 때는 얇은 경계선만으로 "위에 떠 있음"을 알린다.
        // 그림자는 크롬끼리 같은 배경으로 이어지는 레이아웃과 충돌해 지저분해 보인다.
        .overlay(alignment: .trailing) {
            if peeking { Rectangle().fill(Color.pBorder).frame(width: 1) }
        }
        .animation(.easeOut(duration: 0.12), value: peeking)
        .onHover { hovering in
            if state.sidebarMode == .hover { peeking = hovering }
            if !hovering { hoveredId = nil } // 사이드바를 벗어나면 강조·이름 칩 해제(빠져나갈 때 잔상 방지)
        }
    }

    @ViewBuilder
    private func item(_ ws: Workspace, index: Int) -> some View {
        let active = ws.id == state.activeId
        // 백그라운드 활동(●) — 이 워크스페이스의 프로젝트 중 배지된 게 있으면 표시(DESIGN 5절 사이드바 ●).
        let badged = state.badgedWorkspaces.contains(ws.id)
        let hovered = hoveredId == ws.id || menuOpenId == ws.id
        Button {
            state.setActiveId(ws.id)
        } label: {
            HStack(spacing: 6) {
                if effectiveMode == .slim {
                    // 슬림 모드는 아이콘이 없어 색 막대 하나로 상태를 말한다 — 활성은 굵고 진하게,
                    // 비활성은 가늘고 흐리게. (행 배경은 그리지 않는다: 폭이 좁아 배경이 좌우 끝에
                    // 달라붙어 지저분해진다. 막대만으로 충분히 읽힌다.)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(active || badged ? Color.pBorderFocus
                              : Color.pMuted.opacity(hovered ? 0.85 : 0.4))
                        .frame(width: active ? 4 : 3, height: active ? 24 : 18)
                        .animation(Motion.fast, value: active)
                } else {
                    Text(ws.name.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Color.pFg)
                        .frame(width: 22, height: 22)
                        .background(active ? Color.pBorderFocus
                                    : (hovered ? Color.pBtnHover : Color.pBtnActive))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            // 아이콘 우상단 ● 배지(expanded/icon/hover→expanded 공용). 패널색 링으로 아이콘과 분리.
                            if badged {
                                Circle()
                                    .fill(Color.pBorderFocus)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(Color.pPanel, lineWidth: 1.5))
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                if effectiveMode == .expanded {
                    Text(ws.name)
                        .font(.system(size: 13))
                        .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
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
            .background(rowBackground(active: active, hovered: hovered))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 우클릭 → 커스텀 메뉴(이름·경로·복제·닫기). 좌클릭은 그대로 버튼(전환)으로 흐른다.
        .onRightClick { point in
            menuOpenId = ws.id
            MuxaMenuWindow.show(WorkspaceMenu.items(for: ws, state: state), at: point) {
                menuOpenId = nil
            }
        }
        .onHover { hovering in
            // 다른 항목으로 이미 옮겨간 뒤 도착하는 exit는 무시(강조가 깜빡이지 않게).
            if hovering { hoveredId = ws.id } else if hoveredId == ws.id { hoveredId = nil }
        }
        .animation(.easeOut(duration: 0.1), value: hovered)
        // 이름 칩은 항목 바깥(사이드바 우측)에 그린다 — 클릭을 먹지 않게 히트테스트를 끈다.
        // (이전의 .popover는 모달이라 열린 상태에서 첫 클릭이 "팝오버 닫기"로 소비돼 전환이 씹혔다.)
        .overlay(alignment: .leading) {
            // 접힌 모드: 이름 칩. 펼친 모드: 이름이 이미 보이므로 칩 없음(경로는 네이티브 툴팁으로).
            // 메뉴가 열려 있으면 칩을 띄우지 않는다 — 메뉴가 바로 옆에 뜨므로 겹쳐서 지저분해진다.
            if hoveredId == ws.id, menuOpenId == nil, showsNameChip {
                nameChip(ws)
                    .offset(x: width - 6 + Self.chipGap) // 행 leading(패딩 6) 기준 → 사이드바 우측 바깥
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .help(helpText(ws))
    }

    /// 네이티브 툴팁(이름+경로) — 즉시 뜨는 칩의 보조. 개행을 렌더한다.
    private func helpText(_ ws: Workspace) -> String {
        guard let path = ws.path else { return ws.name }
        return "\(ws.name)\n\(displayPath(path, home: SystemPaths.home))"
    }

    /// 접힌 모드에서 호버한 워크스페이스의 이름(+경로)을 사이드바 옆에 띄우는 칩.
    private func nameChip(_ ws: Workspace) -> some View {
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
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.pPanel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 8, x: 2, y: 2)
    }

    /// 항목 배경 — 활성은 채움(호버 시 더 진하게), 비활성은 호버할 때만 옅게 뜬다.
    /// 슬림 모드는 배경을 그리지 않는다 — 폭이 좁아 배경이 좌우 끝에 달라붙는다(막대가 대신 말한다).
    private func rowBackground(active: Bool, hovered: Bool) -> Color {
        if effectiveMode == .slim { return .clear }
        if active { return Color.pBtnActive.opacity(hovered ? 0.9 : 0.6) }
        return hovered ? Color.pBtnHover.opacity(0.7) : Color.clear
    }
}
