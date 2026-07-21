import SwiftUI

/// `cd` 자동완성 드롭다운 — 터미널(Warp·Kiro CLI) 스타일. 폴더를 세로 목록으로 띄우고
/// 하이라이트(↑↓)·Tab 완성·클릭을 받는다. 표면은 커스텀 메뉴·팝오버와 같은 `floatingPanel()`.
///
/// 렌더 전용(controlled) — 후보·선택은 호출부가 소유하고, 여기선 그리기와 hover/클릭만 한다.
struct CdCompletionPopup: View {
    let names: [String]
    /// 키보드로 고른 인덱스(하이라이트). hover와 별개 축 — hover가 들어오면 이 강조는 물러난다.
    let selection: Int
    let onPick: (Int) -> Void
    let onHover: (Int) -> Void

    /// 목록이 길어도 판이 화면을 덮지 않게 — 내부 스크롤로 자른다(≈8줄).
    private static let maxListHeight: CGFloat = RowHeight.tight * 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        row(index: index, name: name)
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)

            // 타입 힌트 푸터 — 무엇을 고르는지(폴더)와 완성 키를 알린다(이미지의 `folder`·`^k` 자리).
            HDivider()
            HStack(spacing: Space.xs) {
                Text("folder").font(.muxa(.nano)).italic().foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.sm)
                Text("↑↓ 선택 · ⇥ 완성").font(.muxa(.nano)).foregroundStyle(Color.pMuted.opacity(0.7))
            }
            .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
        }
        .frame(minWidth: 200)
        .floatingPanel()
    }

    private func row(index: Int, name: String) -> some View {
        let active = index == selection
        return HStack(spacing: Space.sm) {
            Image(systemName: "folder.fill").font(.muxa(.nano))
                .foregroundStyle(active ? Color.pOnBrand : Color.pBrand)
                .frame(width: IconSize.statusSlot)
            Text(name + "/").font(.muxaMono(.caption)).lineLimit(1)
                .foregroundStyle(active ? Color.pOnBrand : Color.pFg)
            Spacer(minLength: Space.xs)
        }
        .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
        .background(active ? Color.pBrand : Color.clear)
        .contentShape(Rectangle())
        .onHover { if $0 { onHover(index) } }
        .onTapGesture { onPick(index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) 폴더로 이동")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPick(index) }
    }
}
