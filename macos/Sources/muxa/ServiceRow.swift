import SwiftUI

/// 서비스 한 줄 — **도크 목록과 팝오버가 같은 행을 쓴다.**
///
/// 둘은 원래 같은 문법("표식 · 이름 · 꼬리표")인데 코드가 갈라져 있었고, 그 사이로 접근성 규칙이 샜다:
/// 팝오버는 글리프를 쓰는데 **도크만 색 점**이라 색맹 사용자에겐 죽은 서비스와 도는 서비스가 같은 줄로
/// 보였다(`ServiceStatusStyle`이 "색만으로 구분하지 않는다"고 선언해 둔 바로 그 규칙 위반).
/// 같은 문법이면 같은 코드여야 한다 — 여기 한 곳에 모은다.
struct ServiceRow: View {
    let service: Service
    let status: ServiceState
    let port: Int?
    /// 보조 줄(명령). 폭이 좁은 도크 목록은 nil — 이름만으로 충분하고, 명령은 헤더에 이미 있다.
    var subtitle: String?
    var selected = false
    /// 사용자가 중단했나 — `.missing`을 "실행 전"이 아니라 "중단됨"으로 갈라 표시한다(`ServiceDisplay`).
    var stopped = false
    /// 행 전체 클릭(도크: 선택).
    let action: () -> Void
    /// hover 토글 — 실행 중이면 중단, 아니면 시작(비파괴). nil이면 hover 액션 없음.
    var onToggleRun: (() -> Void)? = nil

    @State private var hovered = false

    private var isRunning: Bool { status == .running }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: Space.sm) {
                    // 표식은 **글리프**다 — 상태가 바뀌면 모양 자체가 바뀐다(색맹 안전, DESIGN.md).
                    Image(systemName: ServiceDisplay.glyph(status, stopped: stopped))
                        .font(.muxa(.micro))
                        .foregroundStyle(ServiceDisplay.color(status, stopped: stopped))
                        .frame(width: IconSize.statusSlot)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(service.name)
                            .font(.muxa(.label))
                            .foregroundStyle(Color.pFg)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.muxaMono(.caption))
                                .foregroundStyle(Color.pMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: Space.sm)
                    // hover에 토글이 뜨면 꼬리표는 자리를 내준다(출렁임 없이).
                    if !(hovered && onToggleRun != nil),
                       let tail = ServiceDisplay.tail(status, port: port, stopped: stopped) {
                        Text(tail)
                            .font(.muxaMono(.caption))
                            .foregroundStyle(ServiceDisplay.color(status, stopped: stopped))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .accessibilityRow(label: "\(service.name), \(ServiceDisplay.label(status, stopped: stopped))",
                              selected: selected)

            // hover 시 중단/시작 — 삭제 없이도 껐다 켜지게(파괴는 상세 헤더에만).
            if let onToggleRun {
                FooterAction(icon: isRunning ? "stop.fill" : "play.fill",
                             help: isRunning ? "중단 — 등록은 유지" : "시작",
                             action: onToggleRun)
                    .opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .frame(minHeight: RowHeight.row)
        .background {
            if selected { RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pBtnActive) }
        }
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
    }
}
