import SwiftUI

/// 칸 상태 표시 컨트롤 묶음 — 설정 패널의 "칸 상태 표시" 섹션이 담는다.
///
/// 값은 `PaneIndicatorSettings.shared`에 즉시 쓰고, 열린 칸은 그 @Observable을 직접 읽으므로
/// **라이브로 반영된다**(탭 스타일과 달리 imperative reapply가 필요 없다 — SwiftUI Observation).
struct PaneIndicatorControls: View {
    @Bindable var settings: PaneIndicatorSettings

    private let formColumns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3)
    private let motionColumns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4)

    /// 흐름은 바(상·하·좌)에만 유효 — 링·브래킷·코너면 선택해도 펄스로 내려간다.
    private var formSupportsFlow: Bool {
        settings.form == .top || settings.form == .bottom || settings.form == .left
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PaneFormPreview(settings: settings)

            group("형태") {
                LazyVGrid(columns: formColumns, spacing: Space.xs) {
                    ForEach(PaneIndicatorForm.allCases) { formChip($0) }
                }
            }

            group("모션") {
                LazyVGrid(columns: motionColumns, spacing: Space.xs) {
                    ForEach(PaneMotion.allCases) { motionChip($0) }
                }
                sliderRow("속도", value: $settings.speed, range: PaneIndicatorSettings.speedRange,
                          step: 0.1, format: { String(format: "%.1f초", $0) })
                    .opacity(settings.motion == .none ? 0.35 : 1)
                sliderRow("글로우 번짐", value: $settings.glowSpread,
                          range: PaneIndicatorSettings.glowSpreadRange)
                    .opacity(settings.motion == .glow ? 1 : 0.35)
            }

            group("치수") {
                sliderRow("선 두께", value: $settings.thickness, range: PaneIndicatorSettings.thicknessRange)
                // 브래킷 여백은 브래킷·코너 형태에만 유효 — 아닐 땐 흐리게.
                sliderRow("브래킷·코너 여백", value: $settings.bracketInset,
                          range: PaneIndicatorSettings.bracketInsetRange)
                    .opacity(settings.form == .bracket || settings.form == .corner ? 1 : 0.35)
            }

            group("동작") {
                Toggle(isOn: $settings.clearOnFocus) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("포커싱하면 상태표시 지우기").font(.muxa(.caption)).foregroundStyle(Color.pFg)
                        Text("끄면(기본) 칸을 봐도 안 사라진다 — 다음 활동에만 바뀐다")
                            .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(nsColor: Palette.brand))
                .controlSize(.small)
            }
        }
        .footerBlock()
    }

    private func formChip(_ form: PaneIndicatorForm) -> some View {
        let selected = settings.form == form
        return Button { settings.form = form } label: {
            Text(form.label)
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

    /// 흐름을 못 쓰는 형태에선 흐름 칩을 흐리게 — 눌러도 펄스로 내려간다는 걸 시각적으로.
    private func motionChip(_ motion: PaneMotion) -> some View {
        let selected = settings.motion == motion
        let dimmed = motion == .flow && !formSupportsFlow
        return Button { settings.motion = motion } label: {
            Text(motion.label)
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
        .opacity(dimmed ? 0.4 : 1)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double = 1, format: @escaping (Double) -> String = { "\(Int($0))" }) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack {
                Text(title).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.md)
                Text(format(value.wrappedValue)).font(.muxaMono(.caption)).foregroundStyle(Color.pFg)
            }
            Slider(value: value, in: range, step: step).controlSize(.mini).tint(Color(nsColor: Palette.brand))
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(.muxaLabel).tracking(Tracking.label).textCase(.uppercase)
                .foregroundStyle(Color.pMuted)
            content()
        }
    }
}

// MARK: - 프리뷰

/// 미니 칸 하나 — 현재 형태·두께·여백을 대기색(로즈)으로 그린 실물 축소판.
/// 카드 스냅 로직이 필요 없는 독립 렌더(설정 프리뷰 전용). 브래킷은 `BracketShape` 재사용.
private struct PaneFormPreview: View {
    let settings: PaneIndicatorSettings

    var body: some View {
        let color = Color(nsColor: Palette.waiting) // 대기(로즈) 샘플
        let w = CGFloat(settings.thickness)
        let inset = CGFloat(settings.bracketInset)
        RoundedRectangle(cornerRadius: Radius.lg)
            .fill(Color.pBg)
            .frame(height: 64)
            .overlay { decorated(color: color, w: w, inset: inset).clipShape(RoundedRectangle(cornerRadius: Radius.lg)) }
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.pBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// 형태 + 모션 — 실제 칸 테두리와 같은 런타임 타입(FlowBar·PaneMotionEffect)을 재사용해 그대로 미리 본다.
    @ViewBuilder
    private func decorated(color: Color, w: CGFloat, inset: CGFloat) -> some View {
        let motion = settings.motion.resolved(for: settings.form)
        if motion == .flow {
            FlowBar(form: settings.form, color: color, w: w, speed: settings.speed)
        } else {
            formOverlay(color: color, w: w, inset: inset)
                .modifier(PaneMotionEffect(motion: motion, speed: settings.speed,
                                           glowSpread: CGFloat(settings.glowSpread), color: color))
        }
    }

    @ViewBuilder
    private func formOverlay(color: Color, w: CGFloat, inset: CGFloat) -> some View {
        switch settings.form {
        case .ring:
            RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(color, lineWidth: w)
        case .top:
            Rectangle().fill(color).frame(height: w).frame(maxHeight: .infinity, alignment: .top)
        case .bottom:
            Rectangle().fill(color).frame(height: w).frame(maxHeight: .infinity, alignment: .bottom)
        case .left:
            Rectangle().fill(color).frame(width: w).frame(maxWidth: .infinity, alignment: .leading)
        case .bracket:
            BracketShape(inset: inset, arm: 14)
                .stroke(color, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        case .corner:
            Circle().fill(color)
                .frame(width: max(w * 2.5, 5), height: max(w * 2.5, 5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(max(inset, 6))
        }
    }
}
