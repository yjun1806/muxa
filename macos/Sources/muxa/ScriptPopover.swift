import SwiftUI

/// 스크립트 팝오버 — 등록 목록 · 원클릭 백그라운드 실행 · ＋추가. 칩이 "있나 없나(몇 개·무슨 상태)"를
/// 말하고, 여기가 "무엇이 왜"를 말한다(FooterPopover 문법 — 사용량·백그라운드와 같은 틀).
struct ScriptPopover: View {
    let state: AppState
    let project: Project
    /// 실행·추가 요청으로 목록을 떠날 때 팝오버를 닫는다(빈 창이 떠 있지 않게).
    let onDone: () -> Void

    /// 실행 중 행의 경과("12s") 갱신용 — 팝오버는 수명이 짧아 1초 tick이어도 비용이 없다.
    @State private var now = Date()

    private var scripts: [Script] { state.scripts(of: project.id) }

    var body: some View {
        FooterPopover(title: "스크립트", subtitle: "\(scripts.count)개") {
            FooterMark(icon: ScriptStatusStyle.icon)
        } accessory: {
            FooterAction(icon: "plus", help: "스크립트 추가") {
                // 이 팝오버는 별도 NSWindow(FloatingPanelHost)라 `.sheet`가 여기 못 붙는다 —
                // 닫고 원샷 플래그만 세우면 메인 창의 StatusBar가 소비해 시트를 띄운다.
                onDone()
                state.requestAddScript()
            }
        } content: {
            if scripts.isEmpty {
                // 칩이 상시라 빈 목록도 열린다 — 무엇을 하는 기능인지 여기서 말한다(발견 경로).
                Text("빌드·테스트처럼 끝이 있는 명령을 등록하면\n백그라운드로 실행하고 로그를 봅니다. ＋로 추가하세요.")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs)
            }
            ForEach(scripts) { script in
                ScriptRow(script: script, run: state.scriptRuns[script.id], now: now,
                          action: { run(script) },
                          onDelete: { remove(script) })
            }
        }
        .tick(every: 1, into: $now)
    }

    /// 행 클릭 = 백그라운드 실행. 이미 도는 중이면 runScript의 dedup이 새로 안 띄우고 도크의
    /// 출력만 연다 — "실행 중이면 출력 보기"가 같은 경로에서 나온다(두 규칙을 여기서 재구현하지 않는다).
    private func run(_ script: Script) {
        state.runScript(script, in: project.id)
        onDone()
    }

    /// 등록 해제 — 세션(실행 중 프로세스·종료 로그)도 함께 정리된다(AppState.removeScript).
    private func remove(_ script: Script) {
        state.removeScript(script.id, from: project.id)
    }
}
