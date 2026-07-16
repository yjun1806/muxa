import SwiftUI

/// 스크립트 팝오버 — 등록 목록 · 원클릭 실행 · ＋추가. 칩이 "있나 없나(몇 개·무슨 상태)"를
/// 말하고, 여기가 "무엇이 왜"를 말한다(FooterPopover 문법 — 사용량·백그라운드와 같은 틀).
struct ScriptPopover: View {
    let state: AppState
    let project: Project
    let store: TerminalStore
    /// 실행·추가 요청으로 목록을 떠날 때 팝오버를 닫는다(빈 창이 떠 있지 않게).
    let onDone: () -> Void

    /// 실행 중 행의 경과("12s") 갱신용 — 팝오버는 수명이 짧아 1초 tick이어도 비용이 없다.
    @State private var now = Date()

    private var scripts: [Script] { state.scripts(of: project.id) }

    var body: some View {
        FooterPopover(title: "스크립트", subtitle: "\(scripts.count)개") {
            FooterMark(icon: TerminalStore.scriptTabIcon)
        } accessory: {
            FooterAction(icon: "plus", help: "스크립트 추가") {
                // 이 팝오버는 별도 NSWindow(FloatingPanelHost)라 `.sheet`가 여기 못 붙는다 —
                // 닫고 원샷 플래그만 세우면 메인 창의 StatusBar가 소비해 시트를 띄운다.
                onDone()
                state.requestAddScript()
            }
        } content: {
            ForEach(scripts) { script in
                ScriptRow(script: script, run: store.scriptRuns[script.id], now: now,
                          action: { run(script) },
                          onDelete: { remove(script) })
            }
        }
        .tick(every: 1, into: $now)
    }

    /// 행 클릭 = 실행. 이미 도는 중이면 runScript의 dedup이 새로 안 띄우고 그 탭만 앞으로 —
    /// "실행 중이면 탭 포커스"가 같은 경로에서 나온다(두 규칙을 여기서 재구현하지 않는다).
    private func run(_ script: Script) {
        store.runScript(script)
        onDone()
    }

    /// 등록 해제 — 마지막 하나를 지우면 칩(이 팝오버의 호스트)째 사라질 수 있다.
    /// 빈 목록 위에 창만 남지 않게 먼저 닫는다(onDone 주석의 같은 원칙).
    private func remove(_ script: Script) {
        state.removeScript(script.id, from: project.id)
        if scripts.isEmpty { onDone() }
    }
}
