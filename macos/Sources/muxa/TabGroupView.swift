import SwiftUI

/// 그룹 탭의 2단째 — 상단 서브탭 바(개별 문서/커밋) + 선택한 항목의 뷰어.
/// 상단 Bonsplit 탭바 아래에 이 서브탭 줄이 뜬다. 서브탭들은 ZStack+opacity로 살려둬
/// 전환 시 재로드하지 않는다(상단 탭 keepAllAlive와 같은 방식).
struct TabGroupView: View {
    let group: TabGroupState
    let dir: String
    var onCloseItem: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            subTabBar
            Rectangle().fill(Color.pBorder).frame(height: 1)
            content
        }
        .background(Color.pBg)
    }

    private var subTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(group.items) { chip($0) }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color.pPanel)
    }

    private func chip(_ item: GroupItemContent) -> some View {
        let selected = item.id == group.selectedId
        return HStack(spacing: 5) {
            Image(systemName: item.icon).font(.system(size: 10))
            Text(item.title).font(.system(size: 11)).lineLimit(1)
            Button { onCloseItem(item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(selected ? 0.8 : 0.4)
        }
        .foregroundStyle(selected ? Color.pFg : Color.pMuted)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(selected ? Color.pBg : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.pBorder : Color.clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { group.selectedId = item.id }
    }

    /// 서브탭 뷰어들 — 전부 살려두고 선택된 것만 표시(전환 시 상태·스크롤 유지).
    private var content: some View {
        ZStack {
            ForEach(group.items) { item in
                itemView(item)
                    .opacity(item.id == group.selectedId ? 1 : 0)
                    .allowsHitTesting(item.id == group.selectedId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func itemView(_ item: GroupItemContent) -> some View {
        switch item {
        case .file(let target):
            switch target.kind {
            case .markdown, .html: MarkdownView(target: target, chrome: false, onClose: {})
            case .code: CodeView(target: target, chrome: false, onClose: {})
            }
        case .diff(let target):
            DiffView(target: target, dir: dir, chrome: false, onClose: {})
        }
    }
}
