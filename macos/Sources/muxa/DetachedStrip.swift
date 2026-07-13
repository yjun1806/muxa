import SwiftUI

/// 푸터의 "백그라운드" 칩 — **닫았지만 살아 있는 터미널 세션**의 유일한 상시 신호.
///
/// 탭을 닫을 때 안에서 작업이 돌고 있으면 죽이지 않고 남긴다(∞ 지속 세션). 그런데 남긴 걸 어디에도
/// 보여주지 않으면 **눈에 안 보이는 유령**이 된다 — 뭔가 CPU를 먹고 포트를 물고 있는데 사용자는 모른다.
///
/// 서비스 칩·사용량 칩과 같은 문법이다: 칩은 개수만 말하고, 무엇이 왜 남았는지와 되찾기·종료는
/// **클릭해서 여는** 팝오버(DetachedPopover)가 맡는다. 다른 점은 **없으면 자리도 차지하지 않는다**는 것 —
/// 서비스는 "추가하라"는 상시 진입점이지만, 백그라운드 세션은 있을 때만 의미가 있다.
struct DetachedStrip: View {
    let state: AppState
    let project: Project

    @State private var showPopover = false

    private var sessions: [DetachedSession] { project.detached ?? [] }

    var body: some View {
        if !sessions.isEmpty {
            FooterChip(isOpen: $showPopover, help: helpText) {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "moon.zzz")
                        .font(.muxa(.micro))
                        .foregroundStyle(Color.pMuted)
                    Text("\(sessions.count)")
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(Color.pMuted)
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                DetachedPopover(state: state, project: project) { showPopover = false }
            }
        }
    }

    private var helpText: String {
        "백그라운드 터미널 \(sessions.count)개 — 탭은 닫혔지만 안에서 작업이 돌고 있습니다 (클릭해 상세 보기)"
    }
}
