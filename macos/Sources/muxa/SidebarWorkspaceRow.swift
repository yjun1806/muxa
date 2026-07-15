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
            // 레이어 글리프 = "이건 컨테이너다" — 프로젝트 행의 상태 점과 **다른 시각 어휘**라
            // 워크스페이스↔프로젝트가 한눈에 갈린다(색이 아니라 모양으로).
            Image(systemName: "square.stack")
                .font(.muxa(.body, weight: .medium))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
            Text(workspace.name)
                .font(.muxa(.title, weight: .semibold))
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
            // 힌트·+ 는 hover에서만 **보인다**. 하지만 뷰 트리에선 **항상 존재한다** —
            // `if hovered`로 감싸면 hover가 없는 사용자(키보드·VoiceOver·스위치 컨트롤)에게
            // `+`(새 프로젝트)가 접근성 트리에서 통째로 사라져, 확장 트리의 유일한 진입점이 봉쇄된다.
            // 보임은 opacity가, 마우스 히트는 hover가 그대로 가른다(빈 자리를 눌러도 메뉴가 열리지 않게).
            HStack(spacing: Space.xs) {
                // 힌트의 상한은 단축키 표(KeymapResolver)와 한 출처를 쓴다 — 범위를 늘렸는데
                // 힌트만 8에서 멈추는 일이 없게.
                if index < KeymapResolver.workspaceShortcutLimit {
                    Text("⌘\(index + 1)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted)
                        .accessibilityHidden(true) // 단축키 힌트는 장식 — 행 라벨에 섞이면 이름이 지저분해진다
                }
                IconButton(icon: "plus", help: "새 프로젝트") { showAddMenu() }
                    .allowsHitTesting(hovered)
            }
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RowHeight.tight)
        .background(hovered ? Color.pBtnHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        // 행 클릭 = 전환(포커스한 워크스페이스는 펼쳐 보여준다 — 단 다른 건 접지 않는다).
        .onTapGesture { state.setActiveId(workspace.id) }
        .sidebarRow(id: workspace.id, label: "\(workspace.name) 워크스페이스", selected: active,
                    hoveredId: $hoveredId, menuOpenId: $menuOpenId,
                    activate: { state.setActiveId(workspace.id) }) {
            WorkspaceMenu.items(for: workspace, state: state)
        }
        .help(workspace.tooltip)
    }

    /// 디스클로저 — 클릭은 **전환 없이** 그 워크스페이스 하나만 접기/펼치기(활성도 접을 수 있다).
    private var disclosure: some View {
        Button { state.toggleWorkspaceExpansion(workspace.id) } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
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
