import SwiftUI

/// 사용량 팝오버의 **설정 화면** — 헤더 톱니를 누르면 상세 대신 이게 뜬다.
///
/// 표시할 리셋 시각·fable·위치·갱신 주기를 여기서 바꾼다. 값은 `StatusBarSettings`(@Observable)에
/// 바로 쓰이고 UserDefaults에 즉시 영속된다 — "저장" 버튼이 없다(토글이 곧 저장).
struct UsageSettingsView: View {
    @Bindable var settings: StatusBarSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            section("표시") {
                toggleRow("5시간 리셋 시각", detail: "5h 옆에 남은 시간", isOn: $settings.showSessionReset)
                toggleRow("주간 리셋 시각", detail: "wk 옆에 남은 시간", isOn: $settings.showWeeklyReset)
                toggleRow("Fable 세션", detail: "주간 다음에 표시(시간 없음)", isOn: $settings.showFable)
            }
            section("위치") {
                pickerRow("자리", selection: $settings.position) {
                    ForEach(StatusBarSettings.Position.allCases) { pos in
                        Text(pos.label).tag(pos)
                    }
                }
            }
            section("갱신") {
                pickerRow("주기", selection: $settings.refreshIntervalSec) {
                    ForEach(StatusBarSettings.refreshChoices, id: \.self) { sec in
                        Text(intervalLabel(sec)).tag(sec)
                    }
                }
            }
        }
        .footerBlock()
    }

    // MARK: - 조각들

    /// 소섹션 — 대문자 라벨 + 그 아래 행들. 사이드바 소섹션과 같은 어휘(muxaLabel).
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.muxaLabel)
                .tracking(Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Color.pMuted)
            content()
        }
    }

    /// [제목 / 보조]  ────  [스위치]. 보조는 무엇을 켜는지 한 줄로 설명한다.
    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.muxa(.body)).foregroundStyle(Color.pFg)
                Text(detail).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Color(nsColor: Palette.brand))
    }

    /// [제목]  ────  [메뉴]. 좁은 팝오버라 세그먼트 대신 메뉴로 접는다.
    private func pickerRow<V: Hashable, Content: View>(
        _ title: String, selection: Binding<V>, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title).font(.muxa(.body)).foregroundStyle(Color.pFg)
            Spacer(minLength: Space.md)
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.pMuted)
                .fixedSize()
        }
    }

    private func intervalLabel(_ sec: Double) -> String {
        sec < 60 ? "\(Int(sec))초" : "\(Int(sec / 60))분"
    }
}
