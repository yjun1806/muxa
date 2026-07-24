import Bonsplit
import SwiftUI

/// 워크스페이스 하나를 Bonsplit(탭바 + 분할)으로 렌더한다. 각 탭 = 터미널 하나.
/// muxa의 수동 WorkspaceView/TabBarView/Tree를 대체한다.
struct BonsplitWorkspaceView: View {
    let store: TerminalStore
    /// 이 뷰 트리를 그리는 창 — 터미널 서피스가 "내 창이 소유한 것인가"를 판정하는 데 쓴다(→ TermAttach).
    let windowId: String

    var body: some View {
        Group {
            if store.showEmptyState {
                // 프로젝트의 모든 탭이 런타임에 닫혀(exit·⌘W) 살아있는 터미널이 없을 때 — 빈 상태 뷰.
                EmptyProjectView(store: store)
            } else {
                BonsplitView(controller: store.controller) { tab, paneId in
                    tabContent(tab.id, paneId: paneId)
                } emptyPane: { paneId in
                    emptyPane(paneId)
                }
            }
        }
        .onAppear { store.ensureInitialTerminal() }
    }

    /// 탭 내용 — 터미널이거나 diff 뷰어(모달 아님, 이 패인의 탭으로 렌더).
    /// 콘텐츠 위에 활동 플래시 테두리를 얹어, 보이는 칸에서 에이전트 활동(완료·벨·알림)이 나면 그 칸을 짚어준다.
    @ViewBuilder
    private func tabContent(_ tabId: TabID, paneId: PaneID) -> some View {
        paneBody(tabId, paneId: paneId)
            .overlay(PaneBorders(store: store, tabId: tabId, paneId: paneId))
            // 검색 바는 **크롬**이다 — PaneBorders의 베일 위에 얹어야 한다. 아래 두면 칸이 포커스를
            // 잃는 순간(검색창을 열어둔 채 옆 칸을 클릭) 검색창까지 같이 어두워진다.
            .overlay(alignment: .topTrailing) { searchOverlay(tabId) }
            // 복원된 재개 바인딩이 있는 터미널 탭엔 상단에 세션 재개 배너를 얹는다(D2). 바인딩 없으면 아무것도 안 그린다.
            .overlay(alignment: .top) { ResumeOverlay(store: store, tabId: tabId) }
            // ∞ 탭을 작업이 도는 중에 닫으려 하면 이 칸 상단에 확인 배너를 얹는다(NSAlert 대체). 대상 아니면 안 그린다.
            .overlay(alignment: .top) { CloseConfirmOverlay(store: store, tabId: tabId) }
            // 이 ∞ 세션이 다른 프로젝트의 워크트리 안에서 작업 중이면 "옮길까요?" 배너(D31 이동 배지). 대상 아니면 안 그린다.
            .overlay(alignment: .top) { WorktreeMoveOverlay(store: store, tabId: tabId) }
    }

    /// ⌘F 검색 바 — active일 때만 우상단에 뜬다. 터미널 탭에만 있다.
    @ViewBuilder
    private func searchOverlay(_ tabId: TabID) -> some View {
        if case .terminal = store.content(for: tabId) {
            SearchOverlay(term: store.term(for: tabId))
        }
    }

    @ViewBuilder
    private func paneBody(_ tabId: TabID, paneId: PaneID) -> some View {
        switch store.content(for: tabId) {
        case .worktreeLink:
            // 워크트리 링크 탭 — 정보 화면(셸 없음). 대상·액션은 AppState가 스토어에 꽂아 준 위임으로.
            WorktreeLinkPane(store: store, tabId: tabId)
        case .terminal:
            let term = store.term(for: tabId)
            // **[weak store]가 필수다.** 이 클로저는 TerminalRepresentable이 `term.onFocus`에 대입해
            // TermView가 들고 있고, store는 `terms[tabId]`로 그 TermView를 들고 있다 — 강하게 잡으면
            // store ↔ TermView가 서로를 붙잡는 순환이 되어, 프로젝트를 닫아 스토어를 버려도(stores[id]=nil)
            // 아무도 해제되지 않는다. TermView.deinit이 안 돌면 ghostty_surface_free가 호출되지 않아
            // 자식 셸(PTY)·타이머·배지 신호가 영원히 산다. 바로 아래 onContextMenu와 같은 패턴.
            TerminalRepresentable(term: term, windowId: windowId) { [weak store] in
                store?.controller.focusPane(paneId)
                store?.noteTerminalFocused(tabId) // 문서 "Claude에 보내기"의 주입 대상(직전 CC)을 새긴다
            }
            // 칸 우클릭 메뉴 — TermView가 "터미널이 마우스를 캡처했는가"를 코어에 물어 이 콜백을 부를지 정한다.
            // 캡처 중(vim·tmux 등)이면 우클릭은 그 앱으로 가고 여기 오지 않는다.
            .onAppear {
                // 칸 포커스는 TermView.rightMouseDown이 이미 옮긴다(onFocus → focusPane) — 여기선 메뉴만 띄운다.
                term.onContextMenu = { [weak store] point in
                    guard let store else { return }
                    MuxaMenuWindow.show(
                        TerminalPaneMenu.items(store: store, tabId: tabId, paneId: paneId), at: point)
                }
            }
        case .group:
            if let state = store.group(for: tabId) {
                TabGroupView(
                    group: state, dir: store.workingDir ?? "",
                    onFocus: { store.controller.focusPane(paneId) },
                    onCloseItem: { store.closeGroupItem(tabId, itemId: $0) },
                    onCloseOtherItems: { store.closeOtherGroupItems(tabId, keeping: $0) },
                    onOpenFile: { _ = store.openFile($0) },
                    onOpenURL: { _ = store.openURL($0) },
                    onDetachRight: { store.detachGroupItem(tabId, itemId: $0, orientation: .horizontal) },
                    onDetachDown: { store.detachGroupItem(tabId, itemId: $0, orientation: .vertical) },
                    mergeOptions: {
                        store.groupMergeTargets(for: tabId).map { target in
                            MuxaMenuItem(icon: "arrow.triangle.merge", title: "이 그룹 병합 → \(target.summary)") {
                                store.mergeGroup(tabId, into: target.tab)
                            }
                        }
                    },
                    canDrag: { store.subtabFilePath(for: $0) != nil },
                    dragProvider: { store.subtabDragProvider($0, sourceTab: tabId) },
                    onSendToClaude: { store.sendFileToClaude(path: $0) },
                    canSendToClaude: { store.hasInjectionTarget },
                    onSelection: { store.reportDocSelection($0) },
                    onClearContext: { store.clearClaudeContext() }
                )
            }
        }
    }

    /// 분할로 생긴 빈 패인 — 새 터미널을 만든다.
    @ViewBuilder
    private func emptyPane(_ paneId: PaneID) -> some View {
        Button {
            store.newTerminal(inPane: paneId)
        } label: {
            Label("새 터미널", systemImage: "plus")
                .font(.muxa(.title))
                .foregroundStyle(Color.pMuted)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .contentShape(Rectangle())
        .onTapGesture { store.controller.focusPane(paneId) }
    }
}

/// 프로젝트의 모든 탭이 런타임에 닫혀 살아있는 터미널이 없을 때 메인 영역에 뜨는 빈 상태 뷰.
/// 자동으로 새 터미널을 강제 생성하지 않는다(사용자가 의도적으로 다 닫았을 수 있음) — 버튼(⌘T)으로 다시 연다.
/// 앱 최초 실행/복원 시 초기 터미널 보장은 store.ensureInitialTerminal이 그대로 담당한다(이건 런타임에 다 닫은 경우).
private struct EmptyProjectView: View {
    let store: TerminalStore

    var body: some View {
        EmptyState(icon: "terminal", title: "터미널이 없습니다") {
            // 버튼 조판은 공용(EmptyStateButton) — 호출부마다 다시 조판하면 드리프트한다(링크 탭과 공유).
            EmptyStateButton(title: "새 터미널", icon: "plus") {
                store.newTerminal()
            }
            Text("⌘T")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
        }
        .background(Color.pBg)
    }
}

/// 이 칸에 얹는 강조 — **포커스는 밝기로, 알림은 테두리로** 말한다.
///
/// 포커스에 테두리를 쓰지 않는 이유: 그건 **상시** 켜지는 신호다. 그런데 같은 테두리 채널을
/// 에이전트 알림(주황=나를 기다림)도 쓴다. 청록 테두리가 늘 깔려 있으면, 정작 나를 부르는 주황이
/// 그 위에서 경쟁해야 한다 — 강조가 강조를 잡아먹는다.
/// 그래서 포커스는 **베일**(포커스 없는 칸을 살짝 눌러 둠)로 말하고, 테두리는 비워 둔다.
/// **테두리가 떴다 = 무슨 일이 났다**가 성립한다.
/// (그 칸의 활성 탭도 함께 말한다 — 탭 카드의 teal 윤곽·아이콘·굵은 제목. → `BonsplitChrome`)
///
/// 테두리는 직접 그리지 않고 **카드 레이어로 위치·색만 올려보낸다**. 칸 안에서 그리면 카드의
/// 라운드 클립에 모서리가 깎이므로, `paneBorder`(→ `ContentCard`)가 클립 바깥에서 대신 그린다.
///
/// - agent: "지금 이 칸의 상태"(작업중 인디고·대기 로즈·완료 세이지)를 상태별 형태·모션으로 지속 표시.
///   유휴는 안 그린다. (예전의 순간 '활동 플래시'는 제거 — 상태 테두리가 이미 상태를 말한다.)
///
/// Bonsplit은 `keepAllAlive`로 **안 보이는 탭의 뷰도 살려둔다** — preference는 opacity와 무관하게
/// 수집되므로 선택된 탭만 올린다. 안 그러면 숨은 탭의 상태 테두리가 보이는 칸 위에 그려진다.
private struct PaneBorders: View {
    let store: TerminalStore
    let tabId: TabID
    let paneId: PaneID

    var body: some View {
        // 선택 탭 판정은 Bonsplit이 실제로 렌더하는 규칙과 같아야 한다 — 분할·탭 닫기 중엔
        // selectedTabId가 잠깐 nil이 되고, 그때 Bonsplit은 첫 탭을 그린다(우리도 그래야 테두리가 안 깜빡인다).
        let visible = store.controller.selectedTab(inPane: paneId)?.id
            ?? store.controller.tabs(inPane: paneId).first?.id
        if visible == tabId {
            let focused = store.controller.focusedPaneId == paneId
            let activity = store.agentActivity(for: tabId)
            let agent = activity.borderColor.map { Color(nsColor: $0) }
            // 상태별 스타일(라이브) — 작업중·대기·완료 각각 형태·모션·치수가 다르다. idle이면 style=nil(색도 nil이라 안 그림).
            let style = activity.indicatorState.map { PaneIndicatorSettings.shared.style(for: $0) }

            Color.clear
                .paneBorder(id: "agent-\(tabId)",
                            color: agent,
                            lineWidth: CGFloat(style?.thickness ?? 2),
                            form: style?.form ?? .ring,
                            bracketInset: CGFloat(style?.bracketInset ?? 7),
                            motion: style?.motion ?? .none,
                            speed: style?.speed ?? 1.6,
                            glowSpread: CGFloat(style?.glowSpread ?? 18),
                            animation: .easeInOut(duration: 0.25))
                // 포커스 없는 칸을 살짝 눌러 둔다. 칸을 나란히 놓고 대조하는 게 이 앱의 일상이라
                // **약하게** 잡았다 — 안 보이는 칸을 만들면 분할의 의미가 없다.
                .overlay {
                    Color.pPaneVeil
                        .opacity(focused ? 0 : 1)
                        .animation(Motion.fast, value: focused)
                        .allowsHitTesting(false)
                }
        }
    }
}
