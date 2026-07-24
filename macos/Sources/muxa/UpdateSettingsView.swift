import SwiftUI

/// 업데이트 설정 — 자동 확인 토글 + 수동 "지금 확인". 상태(현재 버전·확인 결과)는 `UpdateChecker`가 소유한다.
///
/// 설치본은 업데이트를 알 방법이 폴링뿐이라 자동확인은 **기본 켜짐**이고, 여기서 끌 수 있다(opt-out).
/// "지금 확인"은 자동확인을 꺼도 동작한다 — 명시적 요청이니까. 업데이트가 있으면 **레일에 배지가 뜬다**.
struct UpdateSettingsView: View {
    @Bindable var checker: UpdateChecker

    @State private var checking = false
    @State private var result: UpdateChecker.ManualResult?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SettingToggleRow(title: "자동으로 업데이트 확인",
                             detail: "하루 1회 새 버전을 확인해 레일에 배지로 알립니다",
                             isOn: $checker.autoCheckEnabled)

            HStack(spacing: Space.md) {
                Button(action: check) {
                    Text(checking ? "확인 중…" : "지금 확인")
                        .font(.muxa(.label, weight: .semibold))
                        .foregroundStyle(checking ? Color.pMuted : Color.pBrand)
                }
                .buttonStyle(.plain)
                .clickCursor()
                .disabled(checking)

                if let resultText { Text(resultText).font(.muxa(.caption)).foregroundStyle(resultColor) }
                Spacer(minLength: 0)
                Text("현재 \(AppInfo.version)").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
        }
        .padding(.horizontal, Space.panelInset)
    }

    private func check() {
        checking = true
        result = nil
        Task {
            let r = await checker.checkManually()
            checking = false
            result = r
        }
    }

    /// 확인 결과 한 줄 — 없으면 표시 안 함.
    private var resultText: String? {
        switch result {
        case .none: return nil
        case .upToDate: return "최신 버전입니다"
        case .available(let v): return "새 버전 \(v) — 레일에서 업데이트하세요"
        case .busy: return "업데이트 진행 중입니다"
        case .failed: return "확인 실패 — 네트워크를 확인하세요"
        case .devBuild: return "개발 빌드 — 업데이트 확인 안 함"
        }
    }

    private var resultColor: Color {
        switch result {
        case .available: return Color.pBrand
        case .failed: return Color(nsColor: Palette.gitDeleted)
        default: return Color.pMuted
        }
    }
}
