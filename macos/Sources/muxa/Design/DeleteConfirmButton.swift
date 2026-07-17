import SwiftUI

/// 상세 헤더의 **파괴적 등록 해제** — 아이콘 전용 관례(IconButton)를 지키되, 삭제만 예외로 한 번 더 묻는다.
/// (CLAUDE.md "파괴적 동작은 판정을 좁게, 보존을 넓게" — 되돌릴 수 없는 3중 파괴는 관성 클릭을 막아야 한다.)
///
/// 안전 장치 셋:
///  1. **정직한 문구** — "등록 해제"가 아니라 실제 결과를 말한다("실행 중인 web을 종료하고 등록·로그를 지웁니다").
///  2. **취소가 오른쪽** — 방금 트래시가 있던 자리에 취소를 놓아, 반사적 재클릭이 삭제가 아니라 취소에 걸린다.
///  3. **취소에 기본 포커스** + `role`은 호출부가 접근성으로 감싼다(스크린리더가 확인 UI를 낭독).
struct DeleteConfirmButton: View {
    /// 트래시 hover 툴팁 — 무엇을 지우는지("등록 해제" / "기록 삭제").
    let help: String
    /// 확인 단계 문구 — 실제 파괴 범위를 정직하게.
    let prompt: String
    /// 확정 버튼 라벨("등록 해제").
    let confirmLabel: String
    let action: () -> Void

    @State private var confirming = false
    @FocusState private var cancelFocused: Bool

    var body: some View {
        if confirming {
            HStack(spacing: Space.xs) {
                Text(prompt)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .layoutPriority(-1)
                // 확정은 왼쪽(트래시 자리와 어긋나게) — danger 채움 + 그 위 전경(pOnBrand: 라이트 흰·다크 딥브라운).
                Button { confirming = false; action() } label: {
                    Text(confirmLabel)
                        .font(.muxa(.caption, weight: .semibold))
                        .foregroundStyle(Color.pOnBrand)
                        .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
                        .background(Color.pServiceExited, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain).clickCursor()
                // 취소는 오른쪽(습관 클릭 방어) + 기본 포커스.
                Button { confirming = false } label: {
                    Text("취소")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pFg)
                        .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
                        .background(Color.pBtnHover, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain).clickCursor()
                .focused($cancelFocused)
            }
            .onAppear { cancelFocused = true }
            .onExitCommand { confirming = false } // Esc는 확인부터 취소(도크 닫기보다 우선)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(prompt) 확인하려면 \(confirmLabel), 아니면 취소.")
        } else {
            IconButton(icon: "trash", help: help) { confirming = true }
        }
    }
}
