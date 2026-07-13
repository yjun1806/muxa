import SwiftUI

/// 푸터의 서비스 칩 — **접혀 있을 때의 유일한 상시 신호**.
///
/// 여기는 "문제가 있나 없나"만 말한다(간략). 무엇이 왜 그런지는 hover 팝오버(ServicePopover)가,
/// 실제 로그는 클릭해서 여는 도크(ServiceDock)가 맡는다 — 사용량 칩과 같은 문법이다.
///
/// 서비스마다 칩을 늘어놓으면 푸터가 금세 넘친다(경로·브랜치·사용량과 폭을 다툰다). 그래서
/// **하나로 요약**하고, 죽은 게 하나라도 있으면 그게 요약이 된다(초록 다수에 묻히면 안 된다).
///
/// **요약은 창 전체가 대상이다.** 활성 프로젝트만 세면, 다른 워크스페이스의 dev 서버가 죽어도
/// 거기 들어가야만 알 수 있다 — 그러면 이 신호는 있으나 마나다. 어디 것이 죽었는지는 팝오버가 밝힌다.
struct ServiceStrip: View {
    let state: AppState
    let project: Project

    @State private var hovered = false
    @State private var showPopover = false

    /// 창 전체의 서비스(모든 워크스페이스·프로젝트).
    private var services: [LocatedService] { state.allLocatedServices }

    private var statuses: [ServiceState] {
        services.map { state.serviceMonitor.states[$0.service.id] ?? .missing }
    }

    var body: some View {
        Button {
            showPopover = false
            state.openServiceDock(serviceId: nil)
        } label: {
            label
                .padding(.horizontal, Space.sm)
                .frame(height: RowHeight.tight)
                .background(chipColor, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside
            // hover로 상세를 연다(사용량은 클릭이지만, 서비스는 클릭이 "로그 열기"라 hover에 배정).
            if inside { showPopover = true }
        }
        .animation(Motion.fast, value: hovered)
        .help(helpText)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ServicePopover(state: state, currentProjectId: project.id) { located in
                showPopover = false
                state.revealService(located) // 다른 프로젝트 것이면 그리로 데려간다
            } onAdd: {
                showPopover = false
                state.requestAddService()
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if !TmuxService.isAvailable {
            // tmux가 없어도 **숨기지 않는다** — 숨기면 이 기능이 있는지조차 모른다.
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: "square.stack.3d.up").font(.muxa(.micro))
                Text("서비스").font(.muxa(.label))
            }
            .foregroundStyle(Color.pMuted.opacity(0.6))
        } else if services.isEmpty {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: "square.stack.3d.up").font(.muxa(.micro))
                Text("서비스").font(.muxa(.label))
            }
            .foregroundStyle(Color.pMuted)
        } else {
            let summary = ServiceStatusStyle.summarize(statuses)
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ServiceStatusStyle.glyph(summary))
                    .font(.muxa(.micro))
                    .foregroundStyle(ServiceStatusStyle.color(summary))
                // 개수만 — 이름·포트는 팝오버에서 본다(푸터는 좁다).
                Text("\(services.count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                if deadCount > 0 {
                    // 죽은 게 있으면 몇 개인지까지는 칩에서 말한다 — 열지 않고도 심각도를 안다.
                    Text("· \(deadCount) 종료됨")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pServiceExited)
                }
            }
        }
    }

    private var deadCount: Int {
        statuses.filter { if case .exited(let c) = $0 { return c != 0 } else { return false } }.count
    }

    private var chipColor: Color {
        if showPopover { return Color.pBtnActive }
        return hovered ? Color.pBtnHover : Color.pBtnHover.opacity(0.5)
    }

    private var helpText: String {
        if !TmuxService.isAvailable { return "서비스 — tmux 설치가 필요합니다" }
        if services.isEmpty { return "서비스 추가 — dev 서버처럼 오래 도는 명령" }
        if deadCount > 0 { return "서비스 \(services.count)개 중 \(deadCount)개가 종료됨 — 클릭해 로그 보기" }
        return "서비스 \(services.count)개 실행 중 — 클릭해 로그 보기 (⌘J)"
    }
}
