import SwiftUI

/// 칸 상태 표시 컨트롤 — **상태별(작업중·대기·완료) 아코디언**으로 접어 둔다(설정창이 안 붐비게).
///
/// 값은 `PaneIndicatorSettings.shared`에 즉시 쓰고, 열린 칸은 그 @Observable을 직접 읽으므로
/// 라이브로 반영된다(SwiftUI Observation). 색은 상태 고정 — 여기선 형태·모션·치수만 고른다.
struct PaneIndicatorControls: View {
    @Bindable var settings: PaneIndicatorSettings
    /// 한 번에 하나만 펼친다(아코디언). 기본은 작업중 펼침 — 새로 켠 진행 표시를 바로 보게.
    @State private var open: PaneIndicatorState? = .working

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(PaneIndicatorState.allCases) { state in
                accordion(state)
            }
            HDivider().padding(.vertical, Space.xs)
            focusToggle
        }
        .footerBlock()
    }

    // MARK: 아코디언 한 칸

    @ViewBuilder
    private func accordion(_ state: PaneIndicatorState) -> some View {
        let isOpen = open == state
        let style = settings.style(for: state)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.fast) { open = isOpen ? nil : state }
            } label: {
                HStack(spacing: Space.sm) {
                    Circle().fill(Color(nsColor: state.color)).frame(width: 9, height: 9)
                    Text(state.label).font(.muxa(.body, weight: .medium)).foregroundStyle(Color.pFg)
                    Spacer(minLength: Space.sm)
                    // 접힌 상태 요약 — "상단 바 · 흐름"
                    Text("\(style.form.label) · \(style.motion.label)")
                        .font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(1)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                }
                .padding(.horizontal, Space.panelInset)
                .frame(height: RowHeight.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()

            if isOpen {
                StateStyleEditor(state: state, style: styleBinding(state))
                    .padding(.horizontal, Space.panelInset)
                    .padding(.top, Space.sm)
                    .padding(.bottom, Space.md)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pBtnActive.opacity(isOpen ? 0.4 : 0)))
    }

    private func styleBinding(_ state: PaneIndicatorState) -> Binding<PaneIndicatorStyle> {
        Binding(get: { settings.style(for: state) },
                set: { settings.setStyle($0, for: state) })
    }

    private var focusToggle: some View {
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
        .padding(.horizontal, Space.panelInset)
    }
}

// MARK: - 한 상태의 스타일 편집기 (형태·모션·치수)

private struct StateStyleEditor: View {
    let state: PaneIndicatorState
    @Binding var style: PaneIndicatorStyle

    private let formColumns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3)
    private let motionColumns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4)

    /// 흐름은 바(상·하·좌)에만 유효 — 아니면 눌러도 펄스로 내려간다.
    private var supportsFlow: Bool {
        style.form == .top || style.form == .bottom || style.form == .left
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PaneFormPreview(style: style, color: state.color)

            group("형태") {
                LazyVGrid(columns: formColumns, spacing: Space.xs) {
                    ForEach(PaneIndicatorForm.allCases) { formChip($0) }
                }
            }

            group("모션") {
                LazyVGrid(columns: motionColumns, spacing: Space.xs) {
                    ForEach(PaneMotion.allCases) { motionChip($0) }
                }
                sliderRow("속도", value: $style.speed, range: PaneIndicatorSettings.speedRange,
                          step: 0.1, format: { String(format: "%.1f초", $0) })
                    .opacity(style.motion == .none ? 0.35 : 1)
                sliderRow("글로우 번짐", value: $style.glowSpread, range: PaneIndicatorSettings.glowSpreadRange)
                    .opacity(style.motion == .glow ? 1 : 0.35)
            }

            group("치수") {
                sliderRow("선 두께", value: $style.thickness, range: PaneIndicatorSettings.thicknessRange)
                sliderRow("브래킷·코너 여백", value: $style.bracketInset, range: PaneIndicatorSettings.bracketInsetRange)
                    .opacity(style.form == .bracket || style.form == .corner ? 1 : 0.35)
            }
        }
    }

    private func formChip(_ form: PaneIndicatorForm) -> some View {
        chip(form.label, selected: style.form == form, dimmed: false) { style.form = form }
    }

    private func motionChip(_ motion: PaneMotion) -> some View {
        chip(motion.label, selected: style.motion == motion,
             dimmed: motion == .flow && !supportsFlow) { style.motion = motion }
    }

    private func chip(_ title: String, selected: Bool, dimmed: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

/// 미니 칸 하나 — 현재 스타일을 상태색으로 그린 실물 축소판. 실제 칸과 같은 런타임 타입
/// (`FlowBar`·`PaneMotionEffect`)을 재사용해 형태·모션·속도·번짐이 그대로 미리보기된다.
private struct PaneFormPreview: View {
    let style: PaneIndicatorStyle
    let color: NSColor

    var body: some View {
        let c = Color(nsColor: color)
        let w = CGFloat(style.thickness)
        let inset = CGFloat(style.bracketInset)
        RoundedRectangle(cornerRadius: Radius.lg)
            .fill(Color.pBg)
            .frame(height: 64)
            .overlay { decorated(color: c, w: w, inset: inset).clipShape(RoundedRectangle(cornerRadius: Radius.lg)) }
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.pBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func decorated(color: Color, w: CGFloat, inset: CGFloat) -> some View {
        let motion = style.motion.resolved(for: style.form)
        if motion == .flow {
            FlowBar(form: style.form, color: color, w: w, speed: style.speed)
        } else {
            formOverlay(color: color, w: w, inset: inset)
                .modifier(PaneMotionEffect(motion: motion, speed: style.speed,
                                           glowSpread: CGFloat(style.glowSpread), color: color))
        }
    }

    @ViewBuilder
    private func formOverlay(color: Color, w: CGFloat, inset: CGFloat) -> some View {
        switch style.form {
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
