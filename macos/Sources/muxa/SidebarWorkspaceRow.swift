import AppKit
import SwiftUI

/// 워크스페이스 행 = 트리의 **소섹션 헤더**. 주인공은 아래 프로젝트 행이므로 여기는 조용해야 한다.
///
/// **활성이어도 배경을 채우지 않는다** — 채움(선택)은 프로젝트 행의 언어다. 워크스페이스 활성은
/// 이름 색(pFg)으로만 말한다. Button으로 감싸지 않는 이유: 디스클로저·`+`가 행 클릭보다 먼저
/// 자기 영역의 클릭을 가져가야 하기 때문(행은 contentShape + onTapGesture).
struct SidebarWorkspaceRow: View {
    let state: AppState
    let workspace: Workspace
    /// ⌘n 힌트용 순번(0부터).
    let index: Int
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?

    private var active: Bool { workspace.id == state.activeId }
    private var expanded: Bool { state.isExpanded(workspace.id) }
    private var hovered: Bool { hoveredId == workspace.id || menuOpenId == workspace.id }

    var body: some View {
        let rollup = state.workspaceStatus(workspace)
        HStack(spacing: Space.xs) {
            disclosure
            Text(workspace.name)
                .font(.muxaLabel)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
                .lineLimit(1)
            // 접혀 있을 때만 롤업 — 펼쳐져 있으면 자식 행이 이미 말한다(같은 말을 두 번 하지 않는다).
            if !expanded, rollup != .idle {
                Circle()
                    .fill(ProjectStatusStyle.color(rollup))
                    .frame(width: ProjectStatusStyle.dotSize(rollup),
                           height: ProjectStatusStyle.dotSize(rollup))
            }
            Spacer(minLength: Space.xs)
            // 힌트·+ 는 hover에서만 — 헤더가 상시 시끄러우면 프로젝트 행이 안 보인다.
            if hovered {
                // 힌트의 상한은 단축키 표(KeymapResolver)와 한 출처를 쓴다 — 범위를 늘렸는데
                // 힌트만 8에서 멈추는 일이 없게.
                if index < KeymapResolver.workspaceShortcutLimit {
                    Text("⌘\(index + 1)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted)
                }
                IconButton(icon: "plus", help: "새 프로젝트") { showAddMenu() }
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RowHeight.tight)
        .background(hovered ? Color.pBtnHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        // 행 클릭 = 전환(활성이 되면 파생 규칙으로 자동 펼침 — SidebarTree.isExpanded).
        .onTapGesture { state.setActiveId(workspace.id) }
        .sidebarRow(id: workspace.id, hoveredId: $hoveredId, menuOpenId: $menuOpenId) {
            WorkspaceMenu.items(for: workspace, state: state)
        }
        .help(workspace.tooltip)
    }

    /// 디스클로저 — 클릭은 **전환 없이** 접기/펼치기. 활성 워크스페이스는 접히지 않으므로 비활성으로 둔다
    /// (누를 수 있는데 아무 일도 안 일어나는 거짓 어포던스를 만들지 않는다).
    private var disclosure: some View {
        Button { state.toggleWorkspaceExpansion(workspace.id) } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(active)
    }

    /// `+` 메뉴(새 프로젝트·워크트리·임의 폴더). SwiftUI `Menu`가 아니라 `MuxaMenuWindow`를 쓰는 이유:
    /// hover에서만 존재하는 버튼이라, 메뉴가 열린 사이 hover가 풀리면 버튼(과 메뉴)이 사라진다.
    /// `menuOpenId`가 그동안 강조·peek를 붙든다.
    private func showAddMenu() {
        menuOpenId = workspace.id
        MuxaMenuWindow.show(ProjectAddMenu.items(for: workspace, state: state),
                            at: NSEvent.mouseLocation) { menuOpenId = nil }
    }
}
