import SwiftUI

/// 서비스 도크 **스크립트 탭**의 행 — `ServiceRow`와 같은 문법(선택 알약·글리프·이름·꼬리표)에
/// 상태 어휘만 스크립트 축(`ScriptStatusStyle`). 클릭 = 상세 선택, hover ▶ = 백그라운드 실행.
/// (삭제·재실행은 상세 헤더가 맡는다 — 파괴적 동작을 실수 클릭 거리에 두지 않는다.)
struct ScriptDockRow: View {
    let script: Script
    let run: ScriptRun?
    var selected = false
    /// 클릭 = 상세 선택(실행이 아니다 — 실행은 hover ▶·상세 헤더).
    let action: () -> Void
    /// hover ▶ = 백그라운드 실행(도는 중이면 dedup이 도크 출력으로 수렴). 도는 행엔 안 그린다.
    let onRun: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: Space.sm) {
                    Image(systemName: ScriptStatusStyle.glyph(run?.state))
                        .font(.muxa(.micro))
                        .foregroundStyle(ScriptStatusStyle.color(run?.state))
                        .frame(width: IconSize.statusSlot)
                    Text(script.name)
                        .font(.muxa(.label))
                        .foregroundStyle(Color.pFg)
                        .lineLimit(1)
                    Spacer(minLength: Space.sm)
                    // 도크 목록은 폭이 좁아 경과(초 tick)는 상세 헤더에 맡긴다 — exit 꼬리표만.
                    if let run, run.isFailure, case .finished(let code?, _) = run.state {
                        Text("exit \(code)")
                            .font(.muxaMono(.caption))
                            .foregroundStyle(ScriptStatusStyle.color(run.state))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .accessibilityRow(label: "스크립트 \(script.name), \(ScriptStatusStyle.label(run?.state))",
                              selected: selected)

            // hover ▶ 빠른 실행 — 행 클릭이 "선택"이 되면서 잃은 1클릭 실행을 여기서 되살린다.
            // 도는 중엔 숨긴다(dedup이라 의미 없음). 자리를 항상 예약해 hover에 폭이 출렁이지 않게 opacity로만 켠다.
            if run?.isRunning != true {
                FooterAction(icon: "play", help: "백그라운드 실행", action: onRun)
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
