import SwiftUI

/// 이름이 안 보이는 모드(icon 52 · slim 14)의 **워크스페이스** 항목.
/// (그 아래 프로젝트는 `SidebarProjectIcon`이 그린다 — 접힘 모드에서도 프로젝트가 보여야 한다.)
///
/// icon은 **무채 캡슐 + 이니셜**이다(컬러 사각형 아바타 폐기 — 그건 Slack/Notion의 언어이고,
/// 브랜드색 채움은 크롬을 도형으로 만든다). 색은 상태 점·막대만 쓴다.
struct SidebarIconItem: View {
    let state: AppState
    let workspace: Workspace
    let slim: Bool
    /// 사이드바 폭 — 이름 칩을 사이드바 바깥으로 밀어내는 기준.
    let sidebarWidth: CGFloat
    let showsNameChip: Bool
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?

    private var active: Bool { workspace.id == state.activeId }
    private var hovered: Bool { hoveredId == workspace.id || menuOpenId == workspace.id }

    var body: some View {
        let rollup = state.workspaceStatus(workspace)
        Button { state.setActiveId(workspace.id) } label: {
            Group {
                if slim { slimBar(rollup) } else { iconCapsule(rollup) }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: RowHeight.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(id: workspace.id, hoveredId: $hoveredId, menuOpenId: $menuOpenId) {
            WorkspaceMenu.items(for: workspace, state: state)
        }
        // 이름 칩은 항목 바깥(사이드바 우측)에 그린다 — 클릭을 먹지 않게 히트테스트를 끈다.
        // 메뉴가 열려 있으면 띄우지 않는다(메뉴가 바로 옆에 뜨므로 겹쳐서 지저분해진다).
        .overlay(alignment: .leading) {
            if hoveredId == workspace.id, menuOpenId == nil, showsNameChip {
                SidebarNameChip(title: workspace.name,
                                subtitle: workspace.path.map { displayPath($0, home: SystemPaths.home) })
                    .offset(x: Sidebar.chipOffset(width: sidebarWidth))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .help(workspace.tooltip)
    }

    /// 슬림 막대 — 색은 **신호**(주의·작업중)만 말하고, "지금 보는 곳"은 색이 아니라 **폭·높이**가 말한다.
    ///
    /// 활성을 브랜드색으로 칠하면 두 가지가 깨진다: ① "돌고 있다"(작업중 롤업도 `brand`다)와
    /// "여기 있다"가 같은 색이 되어 아예 구별되지 않는다 ② 활성 그룹 안의 작업중 신호가
    /// 통째로 묻힌다(슬림에선 그게 유일한 신호다).
    private func slimBar(_ rollup: SidebarTree.ProjectStatus) -> some View {
        // 조용한 활성 그룹만 무채로 한 단계 밝힌다 — 색 축을 하나 더 태우지 않고도 "여기"가 읽힌다.
        let color: Color = (rollup == .idle && active) ? .pFg : ProjectStatusStyle.color(rollup)
        return RoundedRectangle(cornerRadius: SlimBar.radius)
            .fill(color)
            .frame(width: (active || hovered) ? SlimBar.widthActive : SlimBar.width,
                   height: active ? SlimBar.heightActive : SlimBar.height)
            .animation(Motion.fast, value: active)
    }

    /// 아이콘 캡슐 — 무채 채움(활성/hover만 밝아진다) + 이니셜, 우상단에 롤업 점.
    private func iconCapsule(_ rollup: SidebarTree.ProjectStatus) -> some View {
        Text(workspace.name.first.map { String($0).uppercased() } ?? "?")
            // `muxaLabel`은 **머리글 전용** 서체다(자간·대문자와 한 세트) — 이니셜은 머리글이 아니다.
            .font(.muxa(.label, weight: .semibold))
            .foregroundStyle(active ? Color.pFg : Color.pMuted)
            .frame(width: IconSize.control, height: IconSize.control)
            .background(active ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(alignment: .topTrailing) {
                // 하위 신호가 있을 때만. 패널색 링으로 아이콘과 분리한다.
                // 점 크기는 상태가 정한다(신호 6 / 유휴 5) — `ProjectStatusStyle`이 단일 출처.
                if rollup != .idle {
                    Circle()
                        .fill(ProjectStatusStyle.color(rollup))
                        .frame(width: ProjectStatusStyle.dotSize(rollup),
                               height: ProjectStatusStyle.dotSize(rollup))
                        .overlay(Circle().stroke(Color.pPanel, lineWidth: RowHeight.hairline))
                        .offset(x: IconSize.dotOffset, y: -IconSize.dotOffset)
                }
            }
    }
}
