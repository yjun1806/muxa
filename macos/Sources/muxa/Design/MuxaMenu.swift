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

/// 커스텀 메뉴 패널의 본문. 항목을 고르면 액션 실행 후 `onDismiss`로 닫는다(닫기 주체는 상위).
struct MuxaMenuView: View {
    let items: [MuxaMenuItem]
    let onDismiss: () -> Void

    /// 메뉴 폭 — 제목이 길어도 흔들리지 않게 고정한다(항목마다 폭이 달라지면 목록이 들쭉날쭉해 보인다).
    static let width: CGFloat = 240

    @State private var hoveredId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                if item.isSeparator {
                    HDivider().padding(.vertical, Space.xs)
                } else {
                    row(item)
                }
            }
        }
        .padding(.vertical, Space.sm)
        .frame(width: Self.width)
        // 표면(배경·모서리·테두리·그림자·바깥 여백)은 `floatingPanel()`이 — 푸터 팝오버와 같은 것을 쓴다.
        // 여기서 직접 그리지 않는다(그러면 둘이 갈라진다).
    }

    private func row(_ item: MuxaMenuItem) -> some View {
        let hovered = item.enabled && hoveredId == item.id
        return HStack(spacing: Space.md) {
            // 아이콘이 없는 항목도 제목 시작선이 같아야 목록이 정렬돼 보인다 — 자리를 항상 잡는다.
            Group {
                if let icon = item.icon { Image(systemName: icon) } else { Color.clear }
            }
            .font(.muxa(.body))
            .frame(width: 16, height: 16)

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
        .onHover { inside in
            if inside { hoveredId = item.id } else if hoveredId == item.id { hoveredId = nil }
        }
        .onTapGesture {
            guard item.enabled else { return }
            onDismiss() // 먼저 닫는다 — 액션이 모달(NSAlert·NSOpenPanel)을 띄우면 메뉴가 뒤에 남는다.
            item.action?()
        }
    }

    private func foreground(_ item: MuxaMenuItem, hovered: Bool) -> Color {
        guard item.enabled else { return Color.pMuted.opacity(0.45) }
        if item.destructive { return Color.pDanger }
        return hovered ? Color.pFg : Color.pFg.opacity(0.9)
    }
}
