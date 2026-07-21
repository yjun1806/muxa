import SwiftUI

/// 훅 미설치·실패를 **전역 푸터에서** 알리고 원클릭 설치를 유도하는 칩.
///
/// 설치 버튼은 원래 주의 인박스(`AttentionInbox`) 안에만 있어 벨을 눌러야 보였다 — 훅이 없으면 muxa는
/// 에이전트 상태를 **추정**만 하는데, 그 사실이 숨어 있었다. 상시 보이는 푸터로 끌어내 드러낸다.
/// **설치되면 사라진다**(할 일이 없으면 자리도 안 차지한다 — 백그라운드 칩과 같은 발견성 철학).
/// 상태 상세·제거는 인박스 푸터가 계속 맡는다(고급 동작이라 상시 노출은 과하다).
///
/// FooterChip은 팝오버 토글 전용이라 못 쓰고, 같은 시각 토큰(`footerChip` 배경·`RowHeight.tight`·
/// `Radius.sm`)만 따른다 — 이건 즉시 액션(설치) 버튼이다.
struct HookInstallChip: View {
    let state: AppState
    @State private var hovered = false

    var body: some View {
        Button { state.installClaudeHooks() } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: icon).font(.muxa(.label))
                Text(label).font(.muxa(.label)).lineLimit(1)
            }
            .foregroundStyle(Color(nsColor: tint))
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(Color.footerChip(isOpen: false, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help("~/.claude/settings.json에 muxa 훅·상태줄을 설치한다 — 알림·에이전트 상태·사용량 추적"
            + "(기존 설정 보존, 백업 생성)")
    }

    private var isFailed: Bool { if case .failed = state.hookStatus { return true }; return false }
    private var icon: String { isFailed ? "exclamationmark.triangle.fill" : "bolt.slash" }
    private var label: String { isFailed ? "훅 설치 실패 — 재시도" : "훅 설치" }
    private var tint: NSColor { isFailed ? Palette.gitDeleted : Palette.brand }
}
