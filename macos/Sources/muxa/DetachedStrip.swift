import SwiftUI

/// 푸터의 "백그라운드" 칩 — **닫았지만 살아 있는 터미널 세션**의 유일한 상시 신호.
///
/// 탭을 닫을 때 안에서 작업이 돌고 있으면 죽이지 않고 남긴다(∞ 지속 세션). 그런데 남긴 걸 어디에도
/// 보여주지 않으면 **눈에 안 보이는 유령**이 된다 — 뭔가 CPU를 먹고 포트를 물고 있는데 사용자는 모른다.
///
/// 서비스 칩·사용량 칩과 같은 문법이다: 칩은 개수만 말하고, 무엇이 왜 남았는지와 되찾기·종료는
/// hover 팝오버가 맡는다. 다른 점은 **없으면 자리도 차지하지 않는다**는 것 — 서비스는 "추가하라"는
/// 상시 진입점이지만, 백그라운드 세션은 있을 때만 의미가 있다.
struct DetachedStrip: View {
    let state: AppState
    let project: Project

    @State private var hovered = false
    @State private var showPopover = false

    private var sessions: [DetachedSession] { project.detached ?? [] }

    var body: some View {
        if !sessions.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "moon.zzz")
                        .font(.muxa(.micro))
                        .foregroundStyle(Color.pMuted)
                    Text("\(sessions.count)")
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(Color.pMuted)
                }
                .padding(.horizontal, Space.sm)
                .frame(height: RowHeight.tight)
                .background(chipColor, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .onHover { inside in
                hovered = inside
                if inside { showPopover = true } // 서비스 칩과 같은 문법 — hover로 상세를 연다
            }
            .animation(Motion.fast, value: hovered)
            .help(helpText)
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                DetachedPopover(state: state, project: project)
            }
        }
    }

    private var chipColor: Color {
        if showPopover { return Color.pBtnActive }
        return hovered ? Color.pBtnHover : Color.pBtnHover.opacity(0.5)
    }

    private var helpText: String {
        "백그라운드 터미널 \(sessions.count)개 — 탭은 닫혔지만 안에서 작업이 돌고 있습니다"
    }
}

/// 백그라운드 세션 상세 — 되찾거나(열기) 버린다(종료). **되찾을 수 없으면 남긴 의미가 없다.**
private struct DetachedPopover: View {
    let state: AppState
    let project: Project

    private var sessions: [DetachedSession] { project.detached ?? [] }
    private let width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            HDivider()
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
        }
        .padding(Space.md)
        .frame(width: width)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            Image(systemName: "moon.zzz").font(.muxa(.micro))
            Text("백그라운드 터미널").font(.muxa(.label, weight: .semibold))
            Spacer()
            Text("\(sessions.count)")
                .font(.muxaMono(.label))
                .foregroundStyle(Color.pMuted)
        }
    }

    private func row(_ session: DetachedSession) -> some View {
        HStack(alignment: .center, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
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
            Spacer(minLength: Space.xs)
            Button("열기") { state.reattachDetached(session, in: project.id) }
                .font(.muxa(.label, weight: .medium))
            Button("종료") { state.killDetached(session.session, from: project.id) }
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
        }
    }
}
