import SwiftUI

/// 커스텀 컨텍스트 메뉴의 항목(값 타입)과 렌더 뷰.
/// 시스템 NSMenu 대신 직접 그리는 이유 = 크롬 팔레트·타이포와 같은 언어로 보이게 하려고(DESIGN.md).
/// 띄우는 일(창·이벤트)은 `MuxaMenuWindow`가, 무엇을 띄울지는 호출부(예: `WorkspaceMenu`)가 정한다.

/// 메뉴 한 줄 — 액션 또는 구분선. 액션은 [아이콘][제목][단축키] 3열이다.
struct MuxaMenuItem: Identifiable {
    let id = UUID()
    /// SF Symbol 이름. nil이면 아이콘 자리만 비워 제목 열을 맞춘다.
    var icon: String?
    var title: String
    /// 우측에 흐리게 붙는 단축키 힌트("⌘⇧C" 등). 표시 전용 — 실제 키 처리는 KeymapResolver 몫.
    var shortcut: String?
    /// 파괴적 동작(삭제·닫기) — 빨강으로 그린다.
    var destructive = false
    var enabled = true
    /// nil이면 구분선.
    var action: (() -> Void)?

    /// 구분선. **`static let`이면 안 된다** — 인스턴스가 하나뿐이라 메뉴 안 모든 구분선이 같은 `id`를 갖고,
    /// `ForEach`가 중복 ID로 렌더를 망친다. 쓸 때마다 새 값을 만든다.
    static var separator: MuxaMenuItem { MuxaMenuItem(title: "", action: nil) }

    var isSeparator: Bool { action == nil }
}

/// 메뉴의 **키보드 이동 판정**(순수). 구분선·비활성 항목을 건너뛴 다음/이전 인덱스를 고른다.
/// NSMenu였다면 시스템이 공짜로 주던 것 — 직접 그리는 이상 우리가 갖고 있어야 하고, 판정이므로 뷰가 아니라 여기 산다.
enum MuxaMenuNav {
    /// 고를 수 있는 항목(구분선 아님 + 활성)의 인덱스들.
    static func selectable(_ items: [MuxaMenuItem]) -> [Int] {
        items.indices.filter { !items[$0].isSeparator && items[$0].enabled }
    }

    /// ↑/↓ 이동 — 현재 선택이 없으면 끝에서 진입한다(↓이면 첫 항목, ↑이면 마지막 항목).
    /// 목록 끝에 닿으면 순환한다(NSMenu와 같은 동작). 고를 항목이 하나도 없으면 nil.
    static func next(from current: Int?, in items: [MuxaMenuItem], forward: Bool) -> Int? {
        let pool = selectable(items)
        guard !pool.isEmpty else { return nil }
        guard let current, let pos = pool.firstIndex(of: current) else {
            return forward ? pool.first : pool.last
        }
        let step = forward ? 1 : pool.count - 1
        return pool[(pos + step) % pool.count]
    }
}

/// 커스텀 메뉴 패널의 본문. 항목을 고르면 액션 실행 후 `onDismiss`로 닫는다(닫기 주체는 상위).
///
/// **키보드·VoiceOver**: 직접 그린 판이라 NSMenu가 주던 ↑↓·Return·VO 진입을 여기서 직접 만든다 —
/// 루트를 focusable로 만들어 `.onKeyPress`로 이동/실행을 받고(판정은 `MuxaMenuNav`), 각 행은
/// 접근성 요소(버튼 트레이트 + 제목 라벨 + 기본 액션)로 노출한다. Esc(닫기)는 `FloatingPanelHost`가 맡는다.
struct MuxaMenuView: View {
    let items: [MuxaMenuItem]
    let onDismiss: () -> Void

    /// 메뉴 폭 — 제목이 길어도 흔들리지 않게 고정한다(항목마다 폭이 달라지면 목록이 들쭉날쭉해 보인다).
    static let width: CGFloat = 240

    @State private var hoveredId: UUID?
    /// 키보드로 고른 항목의 인덱스. 마우스 hover와 별개 축이라 둘 중 하나만 강조된다(hover가 들어오면 비운다).
    @State private var selection: Int?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.isSeparator {
                    HDivider().padding(.vertical, Space.xs)
                } else {
                    row(item, index: index)
                }
            }
        }
        .padding(.vertical, Space.sm)
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        // 포커스 링은 그리지 않는다 — 강조는 행 배경이 이미 말한다(판 전체가 링에 둘러싸이면 흉하다).
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true } // 열자마자 키를 받는다. 선택은 비워 둔다 — 첫 ↓/↑가 진입점을 정한다.
        .onKeyPress(.downArrow) { move(forward: true) }
        .onKeyPress(.upArrow) { move(forward: false) }
        .onKeyPress(.return) { activateSelected() }
        // 표면(배경·모서리·테두리·그림자·바깥 여백)은 `floatingPanel()`이 — 푸터 팝오버와 같은 것을 쓴다.
        // 여기서 직접 그리지 않는다(그러면 둘이 갈라진다).
    }

    private func move(forward: Bool) -> KeyPress.Result {
        guard let next = MuxaMenuNav.next(from: selection, in: items, forward: forward) else { return .ignored }
        selection = next
        hoveredId = nil // 키보드가 잡으면 마우스 강조는 물러난다(두 줄이 동시에 밝지 않게)
        return .handled
    }

    private func activateSelected() -> KeyPress.Result {
        guard let selection, items.indices.contains(selection) else { return .ignored }
        activate(items[selection])
        return .handled
    }

    /// 항목 실행 — **먼저 닫는다**. 액션이 모달(NSAlert·NSOpenPanel)을 띄우면 메뉴가 뒤에 남는다.
    private func activate(_ item: MuxaMenuItem) {
        guard item.enabled, let action = item.action else { return }
        onDismiss()
        action()
    }

    private func row(_ item: MuxaMenuItem, index: Int) -> some View {
        let hovered = item.enabled && (hoveredId == item.id || selection == index)
        return HStack(spacing: Space.md) {
            // 아이콘이 없는 항목도 제목 시작선이 같아야 목록이 정렬돼 보인다 — 자리를 항상 잡는다.
            Group {
                if let icon = item.icon { Image(systemName: icon) } else { Color.clear }
            }
            .font(.muxa(.body))
            .frame(width: IconSize.mark, height: IconSize.mark)

            Text(item.title)
                .font(.muxa(.body))
                .lineLimit(1)

            Spacer(minLength: Space.md)

            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted.opacity(item.enabled ? 0.9 : 0.4))
            }
        }
        .foregroundStyle(foreground(item, hovered: hovered))
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.toolbar)
        .background(hovered ? Color.pBtnHover : Color.clear)
        .contentShape(Rectangle())
        .cursor(item.enabled ? .pointingHand : .arrow) // 비활성 항목은 눌리지 않는다 — 커서가 그걸 먼저 말한다
        .onHover { inside in
            if inside {
                hoveredId = item.id
                selection = nil // 마우스가 잡으면 키보드 선택은 물러난다
            } else if hoveredId == item.id {
                hoveredId = nil
            }
        }
        .onTapGesture { activate(item) }
        // VoiceOver — 직접 그린 행이라 Button이 아니다. 트레이트·라벨·기본 액션을 손으로 단다.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(item) }
    }

    private func foreground(_ item: MuxaMenuItem, hovered: Bool) -> Color {
        guard item.enabled else { return Color.pMuted.opacity(0.45) }
        if item.destructive { return Color.pDanger }
        return hovered ? Color.pFg : Color.pFg.opacity(0.9)
    }
}
