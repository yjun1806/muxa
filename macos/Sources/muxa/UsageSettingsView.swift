import SwiftUI

/// 사용량 팝오버의 **설정 화면** — 헤더 톱니를 누르면 상세 대신 이게 뜬다.
///
/// 네이티브 스위치·드롭다운 대신 muxa 크롬과 같은 결의 커스텀 컨트롤을 쓴다(팔레트·토큰·Motion).
/// 값은 `StatusBarSettings`(@Observable)에 바로 쓰이고 UserDefaults에 즉시 영속된다 — 저장 버튼이 없다.
struct UsageSettingsView: View {
    @Bindable var settings: StatusBarSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            group("위치") {
                // 창을 축소한 스키매틱 — 헤더/푸터 × 좌/우 네 자리를 직접 눌러 고른다.
                PositionPicker(position: $settings.position)
            }
            group("표시") {
                VStack(spacing: Space.sm) {
                    SettingToggleRow(title: "5시간 리셋", detail: "5h 옆에 남은 시간",
                                     isOn: $settings.showSessionReset)
                    SettingToggleRow(title: "주간 리셋", detail: "wk 옆에 남은 시간",
                                     isOn: $settings.showWeeklyReset)
                    SettingToggleRow(title: "Fable 세션", detail: "주간 다음에 표시(시간 없음)",
                                     isOn: $settings.showFable)
                }
            }
            group("갱신 주기") {
                SegmentedPills(
                    options: StatusBarSettings.refreshChoices.map { ($0, intervalLabel($0)) },
                    selection: $settings.refreshIntervalSec
                )
            }
        }
        .footerBlock()
    }

    /// 소섹션 — 대문자 라벨 + 그 아래 내용. 사이드바 소섹션과 같은 어휘(muxaLabel).
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.muxaLabel)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Color.pMuted)
            content()
        }
    }

    private func intervalLabel(_ sec: Double) -> String {
        sec < 60 ? "\(Int(sec))초" : "\(Int(sec / 60))분"
    }
}

// MARK: - 위치 스키매틱

/// 창을 줄인 그림 — 위(헤더 바)·아래(푸터 바)를 좌/우로 갈라 네 자리를 만든다.
/// 고른 자리엔 실제 사용량 칩(✳ ▬)의 미니 프리뷰가 앉아, "여기에 이렇게 뜬다"가 바로 보인다.
private struct PositionPicker: View {
    @Binding var position: StatusBarSettings.Position

    var body: some View {
        VStack(spacing: 0) {
            bar(.headerLeft, .headerRight)
            // 가운데 = 콘텐츠(터미널) 영역. 바 두 개가 이걸 위아래로 감싸 창처럼 읽힌다.
            ZStack {
                Color.pBg
                Text("❯").font(.muxaMono(.caption)).foregroundStyle(Color.pMuted.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Space.md)
            }
            .frame(maxHeight: .infinity)
            bar(.footerLeft, .footerRight)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
    }

    private func bar(_ leading: StatusBarSettings.Position, _ trailing: StatusBarSettings.Position) -> some View {
        HStack(spacing: 0) {
            PositionZone(position: leading, selection: $position)
            Rectangle().fill(Color.pBorder.opacity(0.5)).frame(width: 1)
            PositionZone(position: trailing, selection: $position)
        }
        .frame(height: 26)
        .background(Color.pPanel)
    }
}

/// 네 자리 중 하나 — 누르면 선택. 선택된 자리엔 칩 프리뷰, hover엔 옅은 배경.
private struct PositionZone: View {
    let position: StatusBarSettings.Position
    @Binding var selection: StatusBarSettings.Position

    @State private var hovered = false
    private var selected: Bool { selection == position }

    var body: some View {
        Button { selection = position } label: {
            ZStack {
                (selected ? Color(nsColor: Palette.brand).opacity(0.16)
                          : (hovered ? Color.pBtnHover : Color.clear))
                if selected {
                    // 실제 칩의 축소판 — ✳ 마크 + 미니 막대.
                    HStack(spacing: 3) {
                        ClaudeMark(size: 9)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(nsColor: Palette.brand))
                            .frame(width: 14, height: 3)
                    }
                    .padding(.horizontal, Space.xs)
                    .frame(maxWidth: .infinity, alignment: position.isLeading ? .leading : .trailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: selected)
        .animation(Motion.fast, value: hovered)
        .help(position.label)
    }
}

// MARK: - 커스텀 컨트롤

/// [제목 / 보조]  ────  [pill 스위치]. 행 전체가 탭 영역(작은 스위치만 겨냥 안 해도 된다).
private struct SettingToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.muxa(.body)).foregroundStyle(Color.pFg)
                Text(detail).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: Space.md)
            PillToggle(isOn: isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// 캡슐 스위치 — 켜지면 brand로 차고 손잡이가 오른쪽으로 민다. 색을 지워도 위치로 상태가 읽힌다.
private struct PillToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color(nsColor: Palette.brand) : Color.pBtnActive)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }
            .animation(Motion.fast, value: isOn)
    }
}

/// 세그먼트 pill — 한 줄에 선택지들. 고른 것만 brand로 차고 나머지는 조용하다.
private struct SegmentedPills<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(options, id: \.value) { opt in
                SegmentPill(label: opt.label, selected: opt.value == selection) {
                    selection = opt.value
                }
            }
        }
    }
}

private struct SegmentPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.muxa(.caption, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color(nsColor: Palette.onBrand) : Color.pMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(background, in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: selected)
        .animation(Motion.fast, value: hovered)
    }

    private var background: Color {
        if selected { return Color(nsColor: Palette.brand) }
        return hovered ? Color.pBtnHover : Color.pBtnActive.opacity(0.4)
    }
}
