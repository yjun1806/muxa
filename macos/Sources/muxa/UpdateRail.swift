import AppKit
import SwiftUI

/// 업데이트 레일 진입점 — **업데이트가 있을 때만** 액티비티 레일에 나타나는 눈에 띄는 버튼.
///
/// `idle`이면 아무것도 그리지 않는다(사용자 요청: 없으면 안 보이게). 있으면 상태별 색(새 버전=브랜드,
/// 완료=초록, 실패=빨강)으로 도드라지게 칠하고, 누르면 상세·액션 팝오버(`UpdatePopover`)를 연다.
/// 상태는 `UpdateChecker.shared` 한 값(`phase`)에서만 온다.
struct UpdateRailButton: View {
    let checker: UpdateChecker

    @State private var showPopover = false

    var body: some View {
        if let style = RailStyle(phase: checker.phase) {
            Button { showPopover.toggle() } label: {
                wobbling(style, badge(style))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .muxaTip(style.help)
            .accessibilityLabel(style.help)
            .muxaPopover(isPresented: $showPopover) {
                UpdatePopover(checker: checker, dismiss: { showPopover = false })
            }
        }
    }

    /// 배지 본체 — 색면 + 아이콘 + 상태 점.
    private func badge(_ style: RailStyle) -> some View {
        Image(systemName: style.icon)
            .font(.muxa(.body, weight: .semibold))
            .foregroundStyle(style.tint)
            .frame(width: IconSize.control, height: IconSize.control)
            .background {
                // 도드라지게 — 무채 레일 아이콘들과 달리 옅은 색면을 깐다.
                RoundedRectangle(cornerRadius: Radius.sm).fill(style.tint.opacity(Tint.subtle))
            }
            .overlay(alignment: .topTrailing) { dot(style.tint) }
            .contentShape(Rectangle())
    }

    /// 업데이트 가능일 때만 **주기적으로 좌우로 까딱**거린다 — 짧게 흔들고 잠깐 쉬고 반복(귀엽게, 시선 강제).
    /// 그 외 상태는 정지(계속 흔들면 노이즈). 회전 기준점은 아래쪽 — 종을 흔드는 듯한 결.
    @ViewBuilder
    private func wobbling(_ style: RailStyle, _ view: some View) -> some View {
        if style.wobbles {
            view.keyframeAnimator(initialValue: 0.0, repeating: true) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-11, duration: 0.10)
                    CubicKeyframe(11, duration: 0.12)
                    CubicKeyframe(-8, duration: 0.11)
                    CubicKeyframe(8, duration: 0.11)
                    CubicKeyframe(-4, duration: 0.10)
                    CubicKeyframe(0, duration: 0.10)
                    LinearKeyframe(0, duration: 1.8)   // 쉬는 구간 — 그다음 다시 까딱
                }
            }
        } else {
            view
        }
    }

    /// 상태를 알리는 점 — 아이콘 밖으로 걸치는 작은 알약(알림 배지와 같은 조판).
    private func dot(_ color: Color) -> some View {
        Circle().fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Color.pPanel, lineWidth: 1.5))
            .offset(x: 3, y: -3)
    }
}

/// phase → 레일 표시(아이콘·색·툴팁). idle이면 nil = 렌더 안 함.
private struct RailStyle {
    let icon: String
    let tint: Color
    let help: String
    /// 좌우로 까딱거리는 웨글 애니메이션 여부 — "지금 조치" 상태(업데이트 가능)만 켠다.
    /// 진행·완료·실패는 정적으로 둔다(계속 흔들면 노이즈가 된다).
    let wobbles: Bool

    init?(phase: UpdateChecker.Phase) {
        switch phase {
        case .idle:
            return nil
        case .available(let v):
            icon = "arrow.down.circle.fill"; tint = Color(nsColor: Palette.brand)
            help = "업데이트 가능 · \(v)"; wobbles = true
        case .updating:
            icon = "arrow.triangle.2.circlepath"; tint = Color(nsColor: Palette.borderActivity)
            help = "업데이트 중…"; wobbles = false
        case .updated(let v):
            icon = "checkmark.circle.fill"; tint = Color(nsColor: Palette.gitAdded)
            help = "\(v) 준비됨 · 재시작하면 적용"; wobbles = false
        case .failed:
            icon = "exclamationmark.triangle.fill"; tint = Color(nsColor: Palette.gitDeleted)
            help = "업데이트 실패"; wobbles = false
        }
    }
}

/// 업데이트 상세·액션 팝오버 — 푸터 팝오버와 같은 셸(`FooterPopover`).
struct UpdatePopover: View {
    let checker: UpdateChecker
    let dismiss: () -> Void

    var body: some View {
        FooterPopover(title: "muxa 업데이트", subtitle: subtitle) {
            FooterMark(icon: markIcon)
        } content: {
            switch checker.phase {
            case .idle:
                FooterHint(title: "최신 버전입니다", detail: "현재 \(AppInfo.version).")
            case .available(let v):
                FooterHint(title: "새 버전 \(v)",
                           detail: "현재 \(AppInfo.version). 눌러 백그라운드로 재빌드·설치합니다. 완료 후 muxa를 재시작하면 적용됩니다(재빌드는 수 분 걸릴 수 있습니다).") {
                    action("업데이트", tint: Color.pBrand) { Task { await checker.startUpdate() } }
                }
            case .updating(let v):
                FooterHint(title: "업데이트 중… (\(v))",
                           detail: "백그라운드에서 재빌드하고 있습니다. 이 창을 닫아도 계속됩니다. 완료되면 여기에 다시 표시됩니다.")
            case .updated(let v):
                FooterHint(title: "\(v) 준비됨",
                           detail: "새 버전이 설치됐습니다. muxa를 재시작하면 적용됩니다.") {
                    action("지금 종료하고 재시작 준비", tint: Color.pBrand) { NSApplication.shared.terminate(nil) }
                }
            case .failed(_, let message, let logPath):
                FooterHint(title: "업데이트 실패", detail: message) {
                    HStack(spacing: Space.md) {
                        action("다시 시도", tint: Color.pBrand) { Task { await checker.startUpdate() } }
                        if let logPath {
                            action("로그 보기", tint: Color.pMuted) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch checker.phase {
        case .idle, .available: return "현재 \(AppInfo.version)"
        case .updating: return "재빌드 중"
        case .updated: return "재시작 대기"
        case .failed: return "실패"
        }
    }

    private var markIcon: String {
        switch checker.phase {
        case .failed: return "exclamationmark.triangle"
        case .updated: return "checkmark.circle"
        default: return "arrow.down.circle"
        }
    }

    /// 팝오버 안의 라벨 버튼 — 훅 설치 버튼과 같은 톤(plain + 색 텍스트).
    private func action(_ label: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.muxa(.label, weight: .semibold)).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .clickCursor()
    }
}
