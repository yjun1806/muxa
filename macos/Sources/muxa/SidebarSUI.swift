import SwiftUI

/// 좌측 사이드바 = **워크스페이스 › 프로젝트 2단 트리**(런 큐). 프로젝트 전환의 유일한 경로다.
/// 4모드: expanded/icon/slim/hover. hover는 마우스를 올리면 잠시 expanded로 펼쳐진다 — 콘텐츠를
/// 밀지 않고 위에 뜬다(오버레이, ContentView가 접힌 폭만 예약). peek 중엔 우측 경계선으로 떠 있음을 표시한다.
///
/// 여기는 **컨테이너**다: 모드 분기와 hover/메뉴 상태만 소유하고, 행은 각자의 뷰가 그린다
/// (`SidebarQueueCard` · `SidebarWorkspaceRow` · `SidebarProjectRow` · `SidebarIconItem`).
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

    /// peek 그늘의 세기 — 라이트/다크는 같은 알파로 같은 무게가 안 난다(`Elevation`).
    private var peekShadowOpacity: Double {
        scheme == .dark ? Elevation.Peek.shadowOpacity.dark : Elevation.Peek.shadowOpacity.light
    }

    /// 이름이 보이지 않는 모드 — 호버 시 이름 칩을 띄운다.
    private var showsNameChip: Bool { effectiveMode != .expanded }

    var body: some View {
        Group {
            if effectiveMode == .expanded { tree } else { compact }
        }
        // 슬림(14pt)은 인셋을 더 좁게 — 0이면 강조 배경이 좌우 벽에 붙고, `hInset`을 그대로 쓰면
        // 클릭 영역이 6pt로 쪼그라든다(좌클릭 전환도 우클릭 메뉴도 조준이 힘들어진다).
        .padding(.vertical, Space.sm)
        .padding(.horizontal, effectiveMode == .slim ? Sidebar.slimInset : Sidebar.hInset)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        // **사이드바가 카드에 그림자를 드리운다** — 카드가 스스로 못 하기 때문이다.
        //
        // 사이드바는 카드 *위에* 뜨는 불투명 오버레이라(ContentView의 .overlay), 카드가 왼쪽으로 흘리는
        // 그림자는 이 면에 통째로 가려진다 — 즉 "층은 고도가 만든다"는 말이 정작 **사이드바↔터미널
        // 경계에서만 거짓**이 된다(층이 가장 필요한 자리다). 카드 앞에 틈을 비워 그림자가 설 자리를
        // 주는 방법도 있었지만, 그러면 **보이는 띠(폭+틈)와 사이드바 폭이 어긋나** 항목의 좌우 대칭이
        // 영영 안 맞는다(어느 쪽에 맞춰도 한쪽이 틀린다 — 실측으로 두 번 확인했다).
        // 위 레이어가 아래로 그림자를 던지는 게 물리적으로도 옳다: 틈이 사라져 폭 = 띠가 되고,
        // 가운데가 자명해진다.
        //
        // **peek로 떠 있을 때만 그린다.** 도킹 상태에선 사이드바와 카드가 나란히 붙어 있어 카드의
        // 1px 테두리·둥근 모서리만으로 층이 읽힌다 — 여기에 그림자를 얹으면 사각형 띠가 카드의 둥근
        // 모서리를 못 따라가 아래 코너에서 세로로 삐져나온 노치("딱 잘린 느낌")가 생긴다. 그림자가 진짜
        // 필요한 건 peek로 카드 *위에* 겹쳐 뜰 때뿐이다.
        //
        // **오른쪽 그라디언트로 그린다(`.shadow` 아님).** `.shadow`는 세로 기둥(maxHeight)의 위·아래
        // 모서리에서도 블러돼 크롬 위로 번진다. 그라디언트는 딱 오른쪽만 그려 번짐이 없다.
        .overlay(alignment: .trailing) {
            if peeking {
                LinearGradient(colors: [.black.opacity(peekShadowOpacity), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: Elevation.Peek.shadowRadius + Elevation.Peek.shadowOffsetX)
                    .offset(x: Elevation.Peek.shadowRadius + Elevation.Peek.shadowOffsetX) // 패널 오른쪽 바깥, 카드 위로
                    .allowsHitTesting(false)
            }
        }
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
            SidebarQueueCard(state: state) // 주의가 없으면 아무것도 그리지 않는다
            ForEach(Array(state.workspaces.enumerated()), id: \.element.id) { index, ws in
                VStack(alignment: .leading, spacing: Space.tight) {
                    SidebarWorkspaceRow(state: state, workspace: ws, index: index,
                                        hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                    if state.isExpanded(ws.id) {
                        // **프로젝트 레인**(D안) — 자식 묶음이 옅은 면 위에 앉아 소속을 그린다.
                        // 세로 가이드선·들여쓰기를 대체한다: 선이 아니라 형태가 "한 워크스페이스"를 말하고,
                        // 들여쓰기가 사라져 좁은 사이드바에서 긴 워크트리 이름에 가로 공간을 벌어준다.
                        // 모서리는 안쪽 행(Radius.sm) + 인셋(Space.xs) = Radius.lg — 동심원 규칙.
                        VStack(alignment: .leading, spacing: Space.tight) {
                            ForEach(ws.projects) { project in
                                SidebarProjectRow(state: state, workspace: ws, project: project,
                                                  hoveredId: $hoveredId, menuOpenId: $menuOpenId)
                            }
                        }
                        .padding(Space.xs)
                        .background(Color.pLane)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
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
