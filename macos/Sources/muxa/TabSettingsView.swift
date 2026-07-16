import SwiftUI

/// 탭·활성 탭 스타일 컨트롤 묶음 — 설정 사이드 패널(`SettingsPanel`)의 "탭 스타일" 섹션이 담는다.
///
/// 바꾸면 `onApply`(= `AppState.reapplyTabAppearance`)가 열린 모든 칸에 라이브로 민다 — 재시작 없이 바로 보인다.
struct TabStyleControls: View {
    let settings: TabStyleSettings
    let onApply: () -> Void

    private let styleColumns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // 실물 축소판 — 고른 스타일·치수가 그대로 반영된다(실제 칸에도 동시에 적용된다).
            TabStylePreview(settings: settings)

            group("활성 스타일") {
                LazyVGrid(columns: styleColumns, spacing: Space.xs) {
                    ForEach(TabStyleSettings.ActiveStyle.allCases) { style in
                        styleChip(style)
                    }
                }
            }

            group("치수") {
                sliderRow("좌우 패딩", value: bind(\.horizontalPadding), range: TabStyleSettings.paddingRange)
                sliderRow("모서리 반경", value: bind(\.cornerRadius), range: TabStyleSettings.radiusRange)
                sliderRow("지시선 두께", value: bind(\.indicatorThickness), range: TabStyleSettings.thicknessRange)
            }
        }
        .footerBlock()
    }

    /// 설정 변경 = 즉시 라이브 적용. 슬라이더가 set할 때마다 onApply가 열린 칸을 갱신한다.
    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<TabStyleSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0; onApply() })
    }

    private func styleChip(_ style: TabStyleSettings.ActiveStyle) -> some View {
        let selected = settings.activeStyle == style
        return Button {
            settings.activeStyle = style
            onApply()
        } label: {
            Text(style.label)
                .font(.muxa(.caption, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color(nsColor: Palette.onBrand) : Color.pFg)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(selected ? Color(nsColor: Palette.brand) : Color.pBtnActive.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack {
                Text(title).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.md)
                Text("\(Int(value.wrappedValue))")
                    .font(.muxaMono(.caption)).foregroundStyle(Color.pFg)
            }
            Slider(value: value, in: range, step: 1)
                .controlSize(.mini)
                .tint(Color(nsColor: Palette.brand))
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.muxaLabel).tracking(Tracking.label).textCase(.uppercase)
                .foregroundStyle(Color.pMuted)
            content()
        }
    }
}

// MARK: - 프리뷰

/// 두 개짜리 미니 탭바 — 현재 스타일·치수로 그린 실물 축소판. Bonsplit 렌더를 작게 흉내 낸다.
private struct TabStylePreview: View {
    let settings: TabStyleSettings

    private var knobs: TabStyleKnobs {
        TabStyleSettings.knobs(for: settings.activeStyle,
                               radius: CGFloat(settings.cornerRadius),
                               thickness: CGFloat(settings.indicatorThickness))
    }

    var body: some View {
        let k = knobs
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                miniTab("server.ts", active: true, k: k)
                miniTab("agent", active: false, k: k)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .background(Color.pBtnActive) // 탭바 면
            Color.pBg.frame(height: 24)    // 콘텐츠
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.pBorder, lineWidth: 1))
    }

    private func miniTab(_ title: String, active: Bool, k: TabStyleKnobs) -> some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(active ? Color(nsColor: Palette.brand) : Color.pMuted.opacity(0.6))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.muxa(.caption, weight: active && k.bold ? .semibold : .regular))
                .foregroundStyle(active ? Color.pFg : Color.pMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, CGFloat(settings.horizontalPadding))
        .frame(height: 30)
        .background { if active { activeFill(k) } }
        .overlay(alignment: k.indicatorAtBottom ? .bottom : .top) {
            if active, k.activeIndicatorHeight > 0 {
                RoundedRectangle(cornerRadius: k.indicatorCornerRadius)
                    .fill(Color(nsColor: Palette.brand))
                    .frame(height: k.activeIndicatorHeight)
                    .padding(.horizontal, k.indicatorInset)
            }
        }
    }

    @ViewBuilder
    private func activeFill(_ k: TabStyleKnobs) -> some View {
        if !k.filled {
            Color.clear
        } else if let pill = k.fillCornerRadius {
            RoundedRectangle(cornerRadius: pill)
                .fill(Color.pBg)
                .padding(.vertical, k.fillVInset)
                .padding(.horizontal, k.fillHInset)
        } else {
            UnevenRoundedRectangle(topLeadingRadius: k.tabCornerRadius, topTrailingRadius: k.tabCornerRadius)
                .fill(Color.pBg)
                .padding(.top, k.tabTopInset)
        }
    }
}
