import Bonsplit
import SwiftUI

/// 그룹 탭의 2단째 — 상단 서브탭 바(개별 문서/커밋) + 선택한 항목의 뷰어.
/// 상단 Bonsplit 탭바 아래에 이 서브탭 줄이 뜬다. 서브탭들은 ZStack+opacity로 살려둬
/// 전환 시 재로드하지 않는다(상단 탭 keepAllAlive와 같은 방식).
struct TabGroupView: View {
    let group: TabGroupState
    let dir: String
    /// 이 그룹 탭(칸)이 상호작용(서브탭 클릭·뷰어 클릭)될 때 상위에 알린다 — 그 칸을 활성(포커스)으로 만든다.
    /// 터미널 칸은 TermView가 focusPane을 부르지만 그룹 탭 뷰어는 안 불러서, 클릭해도 활성 칸이 안 옮겨졌다.
    var onFocus: () -> Void = {}
    var onCloseItem: (String) -> Void
    /// 이 서브탭만 남기고 나머지를 닫는다(우클릭 메뉴).
    var onCloseOtherItems: (String) -> Void = { _ in }
    /// 문서 뷰어 안의 로컬 파일 링크를 앱 내 새 탭으로 연다.
    var onOpenFile: (String) -> Void = { _ in }
    /// 문서 뷰어 안의 외부 http(s) 링크를 인앱 브라우저 새 탭으로 연다.
    var onOpenURL: (URL) -> Void = { _ in }
    /// 이 서브탭을 옆/아래 새 분할 패인으로 분리한다.
    var onDetachRight: (String) -> Void = { _ in }
    var onDetachDown: (String) -> Void = { _ in }
    /// 지금 병합할 수 있는 대상(같은 종류·다른 패인 그룹)을 메뉴 항목으로 만든다 — 열 때마다 최신 상태로.
    var mergeOptions: () -> [MuxaMenuItem] = { [] }
    /// 이 서브탭을 드래그로 분리할 수 있나(파일 서브탭만) — 게이트용 값싼 판정.
    var canDrag: (GroupItemContent) -> Bool = { _ in false }
    /// 드래그 시작 시 페이로드(파일 URL + 서브탭 대상)를 만든다.
    var dragProvider: (GroupItemContent) -> NSItemProvider? = { _ in nil }
    /// 이 문서(파일 경로)를 마지막 활성 CC 프롬프트에 `@경로`로 붙인다(우클릭 "Claude에 보내기").
    var onSendToClaude: (String) -> Void = { _ in }
    /// 지금 붙여넣을 살아있는 터미널이 있나 — 메뉴 항목 활성화(메뉴 열 때 평가).
    var canSendToClaude: () -> Bool = { false }
    /// 문서 본문 선택 → IDE 통합(앰비언트 컨텍스트 공유).
    var onSelection: (IdeSelection) -> Void = { _ in }
    /// 이 그룹이 지금 포커스된 패인의 선택 탭인가 — 활성 문서만 IDE 컨텍스트를 재보고한다(그룹 전환 정확도).
    var isActiveGroup: Bool = true
    /// 세션 상세(YJ-7)가 읽을 수집 집합 — 스토어를 직접 물지 않으려 클로저로 받는다.
    var agentDetail: (TabID) -> AgentChangeSet? = { _ in nil }
    /// 상세에서 변경 행을 눌렀을 때 — 패널과 같은 diff 대상을 연다.
    var onOpenDiff: (GitDiffTarget) -> Void = { _ in }
    /// 상세 사이드바 폭·접힘 — 상태는 상위(AppState)가 소유하고 여기는 값·위임만 받는다.
    var detailWidth: CGFloat = 320
    /// 허용 폭 — 상위(AppState)가 소유한 범위를 그대로 받는다(숫자를 여기 또 쓰지 않는다).
    var detailWidthRange: ClosedRange<CGFloat> = 200 ... 560
    var detailCollapsed: Bool = false
    var onCommitDetailWidth: (CGFloat) -> Void = { _ in }
    var onToggleDetailCollapsed: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            subTabBar
            HDivider()
            content
        }
        .background(Color.pBg)
        // 뷰어(WKWebView)가 클릭을 소비해도 simultaneous 제스처는 함께 받는다 — 칸 어디를 눌러도 활성으로.
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    private var subTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(group.items) { chip($0) }
            }
            .padding(.horizontal, 8)
        }
        // 아래 HDivider(1)까지 합쳐 도구 패널 헤더(panelHeader+구분선 = header)와 같은 높이 —
        // 서브탭 줄과 탐색기·Git 헤더의 아래 경계가 한 선에 선다(하드코딩 32는 1pt 어긋났다).
        .frame(height: RowHeight.panelHeader)
        .background(Color.pPanel)
    }

    /// 파일 서브탭은 드래그로 분리 가능(다른 패인 가장자리=분할, 같은 종류 그룹 위=이동). 나머지는 메뉴로만.
    @ViewBuilder
    private func chip(_ item: GroupItemContent) -> some View {
        if canDrag(item) {
            chipContent(item).onDrag { dragProvider(item) ?? NSItemProvider() }
        } else {
            chipContent(item)
        }
    }

    private func chipContent(_ item: GroupItemContent) -> some View {
        let selected = item.id == group.selectedId
        return HStack(spacing: 5) {
            Image(systemName: item.icon).font(.muxa(.caption))
            Text(item.title).font(.muxa(.label)).lineLimit(1)
            Button { onCloseItem(item.id) } label: {
                Image(systemName: "xmark").font(.muxa(.nano, weight: .bold))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .opacity(selected ? 0.8 : 0.4)
            .accessibilityLabel("\(item.title) 닫기")
        }
        .foregroundStyle(selected ? Color.pFg : Color.pMuted)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(selected ? Color.pBg : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(selected ? Color.pBorder : Color.clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .contentShape(Rectangle())
        .clickCursor()
        .onTapGesture { group.selectedId = item.id; onFocus() }
        .accessibilityRow(label: item.title, selected: selected,
                          activate: { group.selectedId = item.id; onFocus() })
        .onRightClick { point in
            let menu = SubTabMenu.items(item, dir: dir, siblings: group.items.count,
                                        onClose: { onCloseItem(item.id) },
                                        onCloseOthers: { onCloseOtherItems(item.id) },
                                        onDetachRight: { onDetachRight(item.id) },
                                        onDetachDown: { onDetachDown(item.id) },
                                        mergeOptions: mergeOptions(),
                                        onSendToClaude: onSendToClaude,
                                        canSend: canSendToClaude())
            MuxaMenuWindow.show(menu, at: point)
        }
    }

    /// 서브탭 뷰어들 — 전부 살려두고 선택된 것만 표시(전환 시 상태·스크롤 유지).
    /// 이 그룹의 상세 항목(에이전트 그룹에만 있다).
    private var detailItem: AgentDetailTarget? {
        for item in group.items { if case .references(let t) = item { return t } }
        return nil
    }

    /// 지금 열려 있는 기준선 diff의 경로 — 사이드바가 그 행을 선택 표시한다.
    private var openDiffPath: String? {
        if case .diff(.baselineFile(_, let path, _)) = group.selected { return path }
        return nil
    }

    /// **에이전트 그룹은 마스터-디테일이다.** 상세를 고르면 풀너비, 파일을 고르면
    /// 상세가 사이드바로 좁아지고 오른쪽에 diff가 선다.
    ///
    /// 상세 뷰는 **한 인스턴스로 유지**한다(폭만 바꾼다) — 두 자리에 각각 그리면 전환할 때마다
    /// 상태가 리셋되고 git 조회가 두 번 돈다.
    private var content: some View {
        HStack(spacing: 0) {
            if let detail = detailItem {
                let full = isDetailSelected
                if full || !detailCollapsed {
                    AgentDetailView(target: detail, setProvider: agentDetail,
                                    root: dir.isEmpty ? nil : dir,
                                    selectedPath: openDiffPath,
                                    compact: !full,
                                    canCollapse: !full,
                                    onExpand: full ? nil : { group.selectedId = GroupItemContent.references(detail).id },
                                    onCollapse: full ? nil : onToggleDetailCollapsed,
                                    onOpenFile: onOpenFile, onOpenURL: onOpenURL,
                                    onOpenDiff: onOpenDiff)
                        .frame(width: full ? nil : liveDetailWidth)
                        .frame(maxWidth: full ? .infinity : nil, maxHeight: .infinity)
                    if !full { sidebarHandle }
                } else {
                    collapsedRail
                }
            }
            if detailItem == nil || openDiffPath != nil || !isDetailSelected {
                ZStack {
                    ForEach(group.items) { item in
                        if !isDetailItem(item) {
                            itemView(item, selected: item.id == group.selectedId)
                                .opacity(item.id == group.selectedId ? 1 : 0)
                                .allowsHitTesting(item.id == group.selectedId)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 드래그 중 실시간 폭(비영속) — 매 프레임 상위 관측 상태를 건드리면 무거운 하위 트리가
    /// 통째로 재평가된다(`ResizablePanel`이 같은 이유로 같은 구조를 쓴다).
    @State private var liveWidth: CGFloat?
    /// 드래그 시작 시점의 폭 — 이동량은 **시작점 기준 누적**이라 기준값을 고정해야 한다.
    /// 매 프레임 직전 값에 더하면 반올림이 쌓여 어긋난다(`ResizablePanel`이 같은 이유로 같은 구조).
    @State private var dragStart: CGFloat?
    private var liveDetailWidth: CGFloat { liveWidth ?? detailWidth }

    /// 사이드바 **오른쪽** 경계 핸들. `ResizablePanel`은 우측 패널용이라 경계가 왼쪽에 있어
    /// 좌측 사이드바에는 방향이 안 맞는다 — 여기선 미러로 직접 그린다.
    private var sidebarHandle: some View {
        Rectangle().fill(Color.pBorder).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 11).contentShape(Rectangle())
                    .cursor(.resizeLeftRight) // onHover는 몇 픽셀만 움직여도 풀린다(`Cursor.swift`)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { g in
                                let start = dragStart ?? detailWidth
                                dragStart = start
                                liveWidth = min(max(start + g.translation.width,
                                                    detailWidthRange.lowerBound),
                                                detailWidthRange.upperBound)
                            }
                            .onEnded { _ in
                                dragStart = nil
                                if let w = liveWidth { onCommitDetailWidth(w) }
                                liveWidth = nil
                            })
            }
    }

    /// 완전히 접었을 때 남는 슬림 레일 — 되돌릴 길이 없으면 접기는 함정이 된다.
    private var collapsedRail: some View {
        VStack(spacing: 0) {
            IconButton(icon: "sidebar.left", help: "상세 펼치기") { onToggleDetailCollapsed() }
                .padding(.top, Space.sm)
            Spacer(minLength: 0)
        }
        .frame(width: RowHeight.toolbar)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.pBorder).frame(width: 1) }
    }

    private var isDetailSelected: Bool {
        guard let d = detailItem else { return false }
        return group.selectedId == GroupItemContent.references(d).id
    }

    private func isDetailItem(_ item: GroupItemContent) -> Bool {
        if case .references = item { return true }
        return false
    }

    @ViewBuilder
    private func itemView(_ item: GroupItemContent, selected: Bool) -> some View {
        switch item {
        case .file(let target):
            // WebView의 isSelected = 서브탭 선택 **AND 이 그룹이 활성**(포커스된 선택 탭) — 그래야 그룹 전환 시
            // 새 그룹의 활성 문서만 컨텍스트를 다시 보고한다. (opacity·BrowserView는 서브탭 선택 그대로.)
            fileItemView(target, selected: selected && isActiveGroup)
        case .diff(let target):
            DiffView(target: target, dir: dir, chrome: false, onClose: {})
        case .web(let tab):
            BrowserView(tab: tab, shouldLoad: selected)
        case .references:
            // 상세는 `content`가 마스터-디테일로 직접 그린다(여기 오지 않는다).
            EmptyView()
        }
    }

    @ViewBuilder
    private func fileItemView(_ target: FileViewTarget, selected: Bool) -> some View {
        switch target.kind {
        case .markdown, .html: MarkdownView(target: target, chrome: false, onClose: {},
                                            onOpenFile: onOpenFile, onOpenURL: onOpenURL,
                                            onSelection: onSelection, isSelected: selected)
        case .code: CodeView(target: target, chrome: false, onClose: {},
                             onSelection: onSelection, isSelected: selected)
        case .image: ImageFileView(target: target, chrome: false, onClose: {})
        case .video: VideoFileView(target: target, chrome: false, onClose: {})
        }
    }
}
