import SwiftUI

/// 설정 사이드 패널 — 탐색기·Git과 같은 도킹 패널(콘텐츠를 밀어내고 좌측 경계로 폭 조절).
///
/// 팝오버가 아니라 패널이라 높이가 바뀌어도 위치가 안 튀고, 넓은 자리에서 프리뷰·슬라이더를 편히 본다.
/// 두 묶음을 담는다 — **탭 스타일**(활성 탭 표시·치수)과 **사용량 표시**(Claude 칩). 바꾸면 즉시 적용된다.
struct SettingsPanel: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            HDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    category("탭 스타일", "활성 탭 표시 방식·치수") {
                        TabStyleControls(settings: .shared,
                                         onApply: { state.reapplyTabAppearance() })
                    }
                    HDivider()
                    category("칸 상태 표시", "칸 테두리 형태·두께·포커스 동작") {
                        PaneIndicatorControls(settings: .shared)
                    }
                    HDivider()
                    category("사용량 표시", "하단·상단 Claude 칩") {
                        UsageSettingsView(settings: .shared)
                    }
                }
                .padding(.vertical, Space.lg)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "gearshape").font(.muxa(.body)).foregroundStyle(Color.pMuted)
            Text("설정").font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
            Spacer(minLength: Space.md)
            IconButton(icon: "xmark", help: "설정 닫기") { state.toggleSettings() }
        }
        .panelBar(height: RowHeight.panelHeader)
    }

    /// 카테고리 — 굵은 제목 + 보조 한 줄, 그 아래 컨트롤 묶음. 컨트롤 안의 소섹션(위치·치수 등)이 하위.
    private func category<Content: View>(_ title: String, _ subtitle: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
                Text(subtitle).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, Space.panelInset)
            content()
        }
    }
}
