import SwiftUI

/// 설정 패널의 섹션 — 외부(사용량 팝오버 톱니 등)에서 "이 섹션 보여줘"로 스크롤·강조 대상을 가리킨다.
enum SettingsSection: String, CaseIterable, Identifiable {
    case tabStyle, paneIndicator, usage
    var id: String { rawValue }
}

/// 설정 사이드 패널 — 탐색기·Git과 같은 도킹 패널(콘텐츠를 밀어내고 좌측 경계로 폭 조절).
///
/// 팝오버가 아니라 패널이라 높이가 바뀌어도 위치가 안 튀고, 넓은 자리에서 프리뷰·슬라이더를 편히 본다.
/// 세 묶음 — **탭 스타일**·**칸 상태 표시**·**사용량 표시**(Claude 칩). 바꾸면 즉시 적용된다.
struct SettingsPanel: View {
    let state: AppState

    /// 방금 스크롤해 온 섹션 — 잠깐 배경을 물들여 시선을 유도한다(1.4초 뒤 사라짐).
    @State private var flash: SettingsSection?

    var body: some View {
        VStack(spacing: 0) {
            header
            HDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        category("탭 스타일", "활성 탭 표시 방식·치수", section: .tabStyle) {
                            TabStyleControls(settings: .shared,
                                             onApply: { state.reapplyTabAppearance() })
                        }
                        HDivider()
                        category("칸 상태 표시", "칸 테두리 형태·두께·포커스 동작", section: .paneIndicator) {
                            PaneIndicatorControls(settings: .shared)
                        }
                        HDivider()
                        category("사용량 표시", "하단·상단 Claude 칩", section: .usage) {
                            UsageSettingsView(settings: .shared)
                        }
                    }
                    .padding(.vertical, Space.lg)
                }
                // 설정이 이 섹션 요청과 함께 열리면(팝오버 톱니) 여기로 스크롤·강조. onAppear=첫 진입, onChange=이미 열린 상태 재요청.
                .onAppear { consumeFocus(proxy) }
                .onChange(of: state.settingsFocus) { _, _ in consumeFocus(proxy) }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
    }

    /// 요청된 섹션으로 스크롤 + 잠깐 플래시. 요청은 한 번 쓰고 비운다(같은 섹션 재요청도 다시 트리거되게).
    /// 스크롤은 한 런루프 미룬다 — onAppear(톱니로 새로 여는 주 경로) 시점엔 ScrollView 콘텐츠가 아직
    /// 배치 전이라 즉시 `scrollTo`가 씹힌다. defer는 "onAppear 안에서 공유 상태 변경" 경고도 함께 피한다.
    private func consumeFocus(_ proxy: ScrollViewProxy) {
        guard let target = state.settingsFocus else { return }
        flash = target
        Task { @MainActor in
            state.settingsFocus = nil
            try? await Task.sleep(nanoseconds: 40_000_000) // 레이아웃 확정 후 스크롤
            withAnimation(Motion.fast) { proxy.scrollTo(target, anchor: .top) }
            try? await Task.sleep(nanoseconds: 1_360_000_000)
            withAnimation(Motion.fast) { if flash == target { flash = nil } }
        }
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
    /// `section`은 스크롤 앵커(`.id`)이자 플래시 강조 대상 키다.
    private func category<Content: View>(_ title: String, _ subtitle: String, section: SettingsSection,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
                Text(subtitle).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, Space.panelInset)
            content()
        }
        .padding(.vertical, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color(nsColor: Palette.brand).opacity(flash == section ? Tint.subtle : 0))
        )
        .id(section)
    }
}
