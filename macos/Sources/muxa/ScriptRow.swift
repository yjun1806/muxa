import SwiftUI

/// 스크립트 한 줄(팝오버 목록) — ServiceRow와 같은 문법: [상태 글리프] [이름 / 명령] [꼬리표].
/// 상태 규칙은 `ScriptStatusStyle`(스크립트 축 SSOT) — 칩과 행이 같은 출처를 읽는다.
struct ScriptRow: View {
    let script: Script
    /// 이 스크립트의 최근 실행(없으면 nil = 실행 전) — 글리프·꼬리표가 여기서 나온다.
    let run: ScriptRun?
    /// 경과 계산 기준 시각 — 부모(팝오버)가 tick으로 갱신해 내려준다(행마다 타이머를 안 만든다).
    let now: Date
    /// 행 전체가 버튼 — 백그라운드 실행(도는 중이면 runScript dedup이 도크 출력으로 수렴).
    let action: () -> Void
    /// 등록 해제(hover 시 휴지통) — 실행 중이면 프로세스도 함께 종료되므로 도는 행에는 그리지 않는다.
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: Space.sm) {
                    // 표식은 **글리프**다 — 상태가 바뀌면 모양 자체가 바뀐다(색맹 안전, DESIGN §2).
                    Image(systemName: ScriptStatusStyle.glyph(run?.state))
                        .font(.muxa(.micro))
                        .foregroundStyle(ScriptStatusStyle.color(run?.state))
                        .frame(width: IconSize.statusSlot)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(script.name)
                            .font(.muxa(.label))
                            .foregroundStyle(Color.pFg)
                            .lineLimit(1)
                        Text(script.command)
                            .font(.muxaMono(.caption))
                            .foregroundStyle(Color.pMuted)
                            .lineLimit(1)
                            // **`.tail`이다(`.middle` 아님)** — 가운데를 접으면 긴 명령의 꼬리
                            // (`&& curl … | sh`)가 사라져 악의적인 명령이 평범해 보인다(ServiceRow와 같은 규칙).
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: Space.sm)
                    if let tail = ScriptStatusStyle.tail(run, now: now) {
                        Text(tail)
                            .font(.muxaMono(.caption))
                            .foregroundStyle(ScriptStatusStyle.color(run?.state))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help(run?.isRunning == true
                  ? "‘\(script.name)’ 실행 중 — 클릭해 출력 보기"
                  : "‘\(script.name)’ 백그라운드 실행 — \(script.command)")
            // 색도 글리프도 스크린리더엔 없다 — 상태를 말로 읽어준다(ServiceRow와 같은 규칙).
            .accessibilityRow(label: "\(script.name), \(ScriptStatusStyle.label(run?.state))")

            // hover 시 실행 표식 — 행 클릭과 같은 동작의 **가시화**다(과녁을 따로 두지 않고
            // 자리를 항상 예약해 hover에 폭이 출렁이지 않게 opacity로만 켠다).
            // 실행 중엔 실행도 해제도 안 그린다 — 실행은 dedup이라 의미가 없고, 해제는 도는
            // 프로세스를 죽이는 파괴적 동작이라 실수 클릭 거리에 두지 않는다(도크 헤더에서만).
            if run?.isRunning != true {
                FooterAction(icon: "play", help: "백그라운드 실행", action: action)
                    .opacity(hovered ? 1 : 0)
                FooterAction(icon: "trash", help: "등록 해제", destructive: true, action: onDelete)
                    .opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .frame(minHeight: RowHeight.row)
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
    }
}

/// 서비스 도크의 스크립트 행 — `ServiceRow`와 같은 문법(선택 알약·글리프·이름·꼬리표)에
/// 상태 어휘만 스크립트 축이다. 클릭 = 상세 선택(실행이 아니다 — 실행·재실행은 상세 헤더의 몫).
struct ScriptDockRow: View {
    let script: Script
    let run: ScriptRun?
    var selected = false
    let action: () -> Void

    var body: some View {
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
                // 도크 목록은 폭이 좁아 경과(초 단위 tick)는 상세 헤더에 맡긴다 — exit 꼬리표만.
                if let run, run.isFailure, case .finished(let code?, _) = run.state {
                    Text("exit \(code)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(ScriptStatusStyle.color(run.state))
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(minHeight: RowHeight.row)
            .background {
                if selected { RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pBtnActive) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .accessibilityRow(label: "스크립트 \(script.name), \(ScriptStatusStyle.label(run?.state))",
                          selected: selected)
    }
}
