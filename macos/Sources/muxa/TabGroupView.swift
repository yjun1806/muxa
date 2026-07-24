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
    private var content: some View {
        ZStack {
            ForEach(group.items) { item in
                itemView(item, selected: item.id == group.selectedId)
                    .opacity(item.id == group.selectedId ? 1 : 0)
                    .allowsHitTesting(item.id == group.selectedId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func itemView(_ item: GroupItemContent, selected: Bool) -> some View {
        switch item {
        case .file(let target):
            fileItemView(target)
        case .diff(let target):
            DiffView(target: target, dir: dir, chrome: false, onClose: {})
        case .web(let tab):
            BrowserView(tab: tab, shouldLoad: selected)
        }
    }

    @ViewBuilder
    private func fileItemView(_ target: FileViewTarget) -> some View {
        switch target.kind {
        case .markdown, .html: MarkdownView(target: target, chrome: false, onClose: {},
                                            onOpenFile: onOpenFile, onOpenURL: onOpenURL)
        case .code: CodeView(target: target, chrome: false, onClose: {})
        case .image: ImageFileView(target: target, chrome: false, onClose: {})
        case .video: VideoFileView(target: target, chrome: false, onClose: {})
        }
    }
}
