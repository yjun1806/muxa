import SwiftUI

/// 패널 안 탭 스위처 — 알약 줄. 좁으면 라벨을 접어 글리프만 남긴다.
///
/// **왜 세그먼티드 `Picker`가 아닌가.** AppKit 기본 렌더러라 반경·높이·선택 채움을 팔레트가
/// 통제하지 못하고, 선택 세그먼트가 **시스템 accent 색**으로 칠해져 "선택은 중립 채움(`btnActive`),
/// 브랜드 wash 금지"(DESIGN §2)를 정면으로 어긴다. 게다가 앱에서 세그먼티드를 쓰는 곳은 Git 패널
/// 하나뿐이었다 — 같은 층의 서비스 도크는 이미 이 알약 문법이다.
///
/// 세그먼티드는 항목이 셋 이상일 때 값을 하는 컨트롤이기도 하다. 둘이면 알약이 더 싸다.
struct PanelTabSwitcher<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    /// 탭 → (라벨, SF Symbol).
    let describe: (Tab) -> (title: String, icon: String)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(labeled: true)
            row(labeled: false)
        }
        .padding(.horizontal, Space.panelInset)
        .padding(.vertical, Space.sm)
    }

    private func row(labeled: Bool) -> some View {
        HStack(spacing: Space.tight) {
            ForEach(tabs) { pill($0, labeled: labeled) }
            Spacer(minLength: 0)
        }
    }

    /// 탭 한 개 — `FooterChip` 알약과 같은 색규칙(선택 = 눌린 상태 유지).
    private func pill(_ tab: Tab, labeled: Bool) -> some View {
        let sel = selection == tab
        let d = describe(tab)
        return Button { selection = tab } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: d.icon).font(.muxa(.label))
                if labeled {
                    Text(d.title).font(.muxa(.label, weight: sel ? .semibold : .regular))
                }
            }
            .foregroundStyle(sel ? Color.pFg : Color.pMuted)
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(Color.footerChip(isOpen: sel, hovered: false),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(d.title)
        .accessibilityLabel(d.title)
        .accessibilityAddTraits(sel ? [.isSelected] : [])
    }
}
