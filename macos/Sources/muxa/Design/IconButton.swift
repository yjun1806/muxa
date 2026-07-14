import SwiftUI

/// 크롬 전용 아이콘 버튼 — 툴바·행 끝의 작은 SF Symbol 버튼.
/// hover하면 색이 진해져(muted → mutedHover) 누를 수 있는 곳임이 드러난다.
struct IconButton: View {
    let icon: String
    var scale: TypeScale = .label
    var weight: Font.Weight = .regular
    var help: String
    /// VoiceOver가 읽을 이름. 없으면 help를 쓴다 — `.help()`는 hint일 뿐이라 label을 안 주면
    /// SF Symbol 기본 설명("plus"·"trash")으로 읽혀 목록의 모든 행이 똑같이 들린다.
    var label: String? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.muxa(scale, weight: weight))
                .foregroundStyle(hovered ? Color(nsColor: Palette.mutedHover) : Color.pMuted)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help(help)
        .accessibilityLabel(label ?? help)
    }
}

/// 배지(알약) — PR 번호·상태처럼 색으로 의미를 나르는 짧은 표식.
/// 배경은 전경색의 옅은 틴트라 색 하나만 정하면 된다.
struct Pill<Content: View>: View {
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Space.xs) {
            content()
        }
        .foregroundStyle(color)
        .padding(.horizontal, Space.sm)
        .frame(height: 16)
        .background(color.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
    }
}
