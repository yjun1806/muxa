import SwiftUI

/// 좌측 사이드바 = **워크스페이스 › 프로젝트 2단 트리**(런 큐). 프로젝트 전환의 유일한 경로다.
/// 4모드: expanded/icon/slim/hover. hover는 마우스를 올리면 잠시 expanded로 펼쳐진다 — 콘텐츠를
/// 밀지 않고 위에 뜬다(오버레이, ContentView가 접힌 폭만 예약). peek 중엔 우측 경계선으로 떠 있음을 표시한다.
///
/// 여기는 **컨테이너**다: 모드 분기와 hover/메뉴 상태만 소유하고, 행은 각자의 뷰가 그린다
/// (`SidebarQueueHeader` · `SidebarWorkspaceRow` · `SidebarProjectRow` · `SidebarIconItem`).
/// 펼침 상태는 뷰가 아니라 `AppState`가 소유한다(영속 — 규칙은 순수 함수 `SidebarTree`).
struct SidebarSUI: View {
    let state: AppState
    /// 그림자 불투명도가 라이트/다크에서 다르다(알파는 동적 NSColor로 못 싣는다 — `CardElevation`과 같은 사정).
    @Environment(\.colorScheme) private var scheme
    @State private var peeking = false
    /// 지금 마우스가 올라간 행(워크스페이스·프로젝트가 같은 id 공간을 쓴다) — 강조 + 이름 칩 대상.
    @State private var hoveredId: String?
    /// 우클릭/+ 메뉴가 열려 있는 행 — 강조를 유지하고, hover 모드에선 사이드바를 펼친 채로 붙든다
    /// (메뉴는 별도 창이라 마우스가 사이드바를 벗어나므로, 이게 없으면 메뉴만 남고 사이드바가 접힌다).
    @State private var menuOpenId: String?

    private var effectiveMode: SidebarMode {
        (state.sidebarMode == .hover && (peeking || menuOpenId != nil)) ? .expanded : state.sidebarMode
    }

    private var width: CGFloat { effectiveMode.baseWidth }

    private var shadowOpacity: Double {
        scheme == .dark ? Elevation.Peek.shadowOpacity.dark : Elevation.Peek.shadowOpacity.light
    }

    /// 이름이 보이지 않는 모드 — 호버 시 이름 칩을 띄운다.
    private var showsNameChip: Bool { effectiveMode != .expanded }

    var body: some View {
        Group {
            if effectiveMode == .expanded { tree } else { compact }
        }
        // 슬림(14pt)은 좌우 패딩을 빼야 항목이 사이드바 폭을 다 쓴다 — 안 그러면 클릭 영역이 2pt로 쪼그라들어
        // 좌클릭 전환도, 우클릭 메뉴도 조준이 사실상 불가능해진다(색 막대는 그 영역 밖으로 그려져 멀쩡해 보인다).
        .padding(.vertical, Space.sm)
        .padding(.horizontal, effectiveMode == .slim ? 0 : Sidebar.hInset)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        // peek로 펼쳐지면 **콘텐츠 카드 위에** 뜬다 — 카드 고도가 못 닿는 유일한 자리다(사이드바가 카드보다 위 레이어).
        // 남는 신호가 1px 하선뿐이면(다크 border↔bg 1.62:1) 2단 트리가 터미널에 얹힌 것처럼 보인다.
        // 그래서 여기서만 그림자를 준다 — 오른쪽으로만(`Elevation.Peek`). 도킹 상태(peeking=false)엔 0이라
        // 크롬끼리 이어지는 자리에 그늘이 지지 않는다(예전에 그림자를 뺐던 이유가 그것이다).
        .shadow(color: .black.opacity(peeking ? shadowOpacity : 0),
                radius: Elevation.Peek.shadowRadius,
                x: peeking ? Elevation.Peek.shadowOffsetX : 0)
        .overlay(alignment: .trailing) {
            if peeking { Rectangle().fill(Color.pBorder).frame(width: RowHeight.hairline) }
        }
        .animation(Motion.fast, value: peeking)
        .onHover { hovering in
            if state.sidebarMode == .hover { peeking = hovering }
            if !hovering { hoveredId = nil } // 사이드바를 벗어나면 강조·이름 칩 해제(빠져나갈 때 잔상 방지)
        }
    }

    /// 2단 트리 — 그룹 사이는 벌리고(groupGap), 그룹 안은 촘촘히(tight). **간격이 위계다.**
    private var tree: some View {
        VStack(alignment: .leading, spacing: Space.groupGap) {
            SidebarQueueHeader(state: state) // 주의가 없으면 아무것도 그리지 않는다
            ForEach(Array(state.workspaces.enumerated()), id: \.element.id) { index, ws in
                VStack(alignment: .leading, spacing: Space.tight) {
                    SidebarWorkspaceRow(state: state, workspace: ws, index: index,
                                        hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                    if state.isExpanded(ws.id) {
                        ForEach(ws.projects) { project in
                            SidebarProjectRow(state: state, workspace: ws, project: project,
                                              hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    /// icon(52) · slim(14) — 이름이 안 보이는 모드. **여기도 2단이다**: 이름이 사라졌을 뿐 트리는 같다.
    /// (워크스페이스만 그리면 접힌 모드에선 프로젝트 전환·닫기·워크트리 생성에 마우스로 닿을 방법이
    ///  하나도 없어진다 — 그 역할을 하던 상단 프로젝트 탭바가 사라졌기 때문이다.)
    private var compact: some View {
        VStack(alignment: .leading, spacing: Space.groupGap) {
            ForEach(state.workspaces) { ws in
                VStack(alignment: .leading, spacing: Space.tight) {
                    SidebarIconItem(state: state, workspace: ws, slim: effectiveMode == .slim,
                                    sidebarWidth: width, showsNameChip: showsNameChip,
                                    hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                    if state.isExpanded(ws.id) {
                        ForEach(ws.projects) { project in
                            SidebarProjectIcon(state: state, workspace: ws, project: project,
                                               sidebarWidth: width, showsNameChip: showsNameChip,
                                               hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                        }
                    }
                }
            }
            Spacer()
        }
    }
}
