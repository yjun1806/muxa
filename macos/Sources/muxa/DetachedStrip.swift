import SwiftUI

/// 푸터의 "백그라운드" 칩 — **닫았지만 살아 있는 터미널 세션**의 유일한 상시 신호.
///
/// 탭을 닫을 때 안에서 작업이 돌고 있으면 죽이지 않고 남긴다(L3). 그런데 남긴 걸 어디에도 보여주지
/// 않으면 **눈에 안 보이는 유령**이 된다 — 뭔가 CPU를 먹고 포트를 물고 있는데 사용자는 모른다.
/// 그래서 서비스 칩과 같은 문법으로, 있으면 자리를 차지하고 없으면 사라진다.
///
/// 여기서는 개수만 말한다. 무엇이 왜 남았는지와 되찾기·종료는 팝오버가 맡는다.
struct DetachedStrip: View {
    let state: AppState
    let project: Project

    @State private var showPopover = false

    private var sessions: [DetachedSession] { project.detached ?? [] }

    var body: some View {
        if !sessions.isEmpty {
            Button { showPopover.toggle() } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "moon.zzz")
                        .font(.muxa(.caption))
                    Text("백그라운드 \(sessions.count)")
                        .font(.muxa(.label))
                }
                .foregroundStyle(Color.pMuted)
                .padding(.horizontal, Space.sm)
                .frame(height: RowHeight.tight)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                DetachedPopover(state: state, project: project)
            }
        }
    }
}

/// 남긴 세션 목록 — 되찾거나(열기) 버린다(종료). **되찾을 수 없으면 남긴 의미가 없다.**
private struct DetachedPopover: View {
    let state: AppState
    let project: Project

    private var sessions: [DetachedSession] { project.detached ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("백그라운드 터미널")
                .font(.muxa(.body, weight: .medium))
            Text("탭은 닫혔지만 안에서 작업이 돌고 있어 살려둔 세션입니다.")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)

            Divider()

            ForEach(sessions) { session in
                HStack(spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.command)
                            .font(.muxaMono(.label))
                        if let cwd = session.cwd {
                            Text(cwd)
                                .font(.muxa(.caption))
                                .foregroundStyle(Color.pMuted)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    Spacer(minLength: Space.md)

                    Button("열기") {
                        state.reattachDetached(session, in: project.id)
                    }
                    .buttonStyle(.plain)
                    .font(.muxa(.label, weight: .medium))
                    .foregroundStyle(Color.pBorderFocus)

                    Button("종료") {
                        state.killDetached(session.session, from: project.id)
                    }
                    .buttonStyle(.plain)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                }
            }
        }
        .padding(Space.md)
        .frame(minWidth: 320)
    }
}
