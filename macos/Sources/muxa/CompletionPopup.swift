import SwiftUI

/// 자동완성 드롭다운 — 터미널(Warp·Kiro CLI) 스타일. 세로 목록 + 하이라이트(↑↓·hover) + 타입 힌트 푸터.
/// **cd 경로 완성**과 **명령 이름 완성**이 공유한다(구조가 같다 — 아이콘·제목·부제·타입 라벨만 다르다).
/// 표면은 커스텀 메뉴·팝오버와 같은 `floatingPanel()`. 렌더 전용(controlled) — 후보·선택은 호출부가 소유.
struct CompletionPopup: View {
    /// 한 줄 — 아이콘 + 제목 (+ 명령 완성이면 부제). 경로 완성은 부제 없이 폴더만.
    struct Item: Identifiable {
        let glyph: String
        /// 아이콘을 브랜드색으로(경로=폴더). false면 muted.
        let brandGlyph: Bool
        let title: String
        let subtitle: String?
        var id: String { title + "\u{1}" + (subtitle ?? "") }
    }

    let items: [Item]
    /// 푸터 좌측 타입 라벨("folder" · "command").
    let typeLabel: String
    /// 키보드로 고른 인덱스(하이라이트). hover와 별개 축.
    let selection: Int
    let onPick: (Int) -> Void
    let onHover: (Int) -> Void

    /// 목록이 길어도 판이 화면을 덮지 않게 — 내부 스크롤로 자른다(≈8줄).
    private static let maxListHeight: CGFloat = RowHeight.tight * 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        row(index: index, item: item)
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)

            // 타입 힌트 푸터 — 무엇을 고르는지와 완성 키를 알린다(이미지의 `folder`·`^k` 자리).
            HDivider()
            HStack(spacing: Space.xs) {
                Text(typeLabel).font(.muxa(.nano)).italic().foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.sm)
                Text("↑↓ 선택 · ⇥ 완성").font(.muxa(.nano)).foregroundStyle(Color.pMuted.opacity(0.7))
            }
            .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
        }
        .frame(minWidth: 220)
        .floatingPanel()
    }

    private func row(index: Int, item: Item) -> some View {
        let active = index == selection
        return HStack(spacing: Space.sm) {
            Image(systemName: item.glyph).font(.muxa(.nano))
                .foregroundStyle(active ? Color.pOnBrand : (item.brandGlyph ? Color.pBrand : Color.pMuted))
                .frame(width: IconSize.statusSlot)
            Text(item.title).font(.muxaMono(.caption)).lineLimit(1)
                .foregroundStyle(active ? Color.pOnBrand : Color.pFg)
            if let subtitle = item.subtitle {
                Spacer(minLength: Space.sm)
                Text(subtitle).font(.muxa(.nano)).lineLimit(1)
                    .foregroundStyle(active ? Color.pOnBrand.opacity(0.8) : Color.pMuted)
            } else {
                Spacer(minLength: Space.xs)
            }
        }
        .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
        .background(active ? Color.pBrand : Color.clear)
        .contentShape(Rectangle())
        .onHover { if $0 { onHover(index) } }
        .onTapGesture { onPick(index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.subtitle.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPick(index) }
    }
}
