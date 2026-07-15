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
    /// 행 전체가 버튼이다(도크: 선택 / 팝오버: 그 서비스로 이동).
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                // 표식은 **글리프**다 — 상태가 바뀌면 모양 자체가 바뀐다(색맹 안전, DESIGN.md).
                Image(systemName: ServiceStatusStyle.glyph(status))
                    .font(.muxa(.micro))
                    .foregroundStyle(ServiceStatusStyle.color(status))
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
                            // **`.tail`이다(`.middle` 아님)** — 가운데를 접으면 긴 명령의 뒷부분(진짜 실행되는 것)이
                            // 사라져 악의적인 명령이 평범해 보인다. 앞부터 보이고 뒤가 잘리는 편이 정직하다.
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: Space.sm)
                if let tail = ServiceStatusStyle.tail(status, port: port) {
                    Text(tail)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(ServiceStatusStyle.color(status))
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(minHeight: RowHeight.row)
            // 선택 채움은 둥근 알약이다(각지지 않게). 좌우 여백은 **감싸는 스코프**가 준다
            // (카드/스코프의 가로 인셋) — 여기선 행 폭을 채우되 모서리만 둥글린다.
            .background {
                if selected { RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pBtnActive) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        // 색도 글리프도 스크린리더엔 없다 — 상태를 말로 읽어준다.
        .accessibilityRow(label: "\(service.name), \(ServiceStatusStyle.label(status))", selected: selected)
    }
}
