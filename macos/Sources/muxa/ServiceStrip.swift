import SwiftUI

/// 푸터의 서비스 칩 — **접혀 있을 때의 유일한 상시 신호**.
///
/// 여기는 "문제가 있나 없나"만 말한다(간략). 무엇이 왜 그런지는 **클릭해서 여는** 팝오버(ServicePopover)가,
/// 실제 로그는 팝오버가 여는 도크(ServiceDock)가 맡는다 — 사용량 칩과 같은 문법이다.
///
/// **왜 hover가 아니라 클릭인가.** 마우스가 스치기만 해도 창이 뜨면 푸터 위를 지나갈 때마다 방해가 된다.
/// hover는 배경색까지만(누를 수 있음), 여는 건 클릭이다. 대신 칩 클릭이 하던 "도크 열기"는 사라지지 않고
/// 팝오버 헤더의 버튼과 행 클릭으로 옮겼다(⌘J도 그대로).
///
/// 서비스마다 칩을 늘어놓으면 푸터가 금세 넘친다(경로·브랜치·사용량과 폭을 다툰다). 그래서
/// **하나로 요약**하고, 죽은 게 하나라도 있으면 그게 요약이 된다(초록 다수에 묻히면 안 된다).
struct ServiceStrip: View {
    let state: AppState
    let project: Project
    /// 서비스가 도는 디렉터리 — 팝오버의 재시작에 필요하다.
    let cwd: String?

    @State private var showPopover = false

    private var services: [Service] { state.services(of: project.id) }

    private var statuses: [ServiceState] {
        services.map { state.serviceMonitor.states[$0.id] ?? .missing }
    }

    var body: some View {
        FooterChip(isOpen: $showPopover, help: helpText) {
            label
        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ServicePopover(state: state, project: project, cwd: cwd) { serviceId in
                showPopover = false
                state.openServiceDock(serviceId: serviceId)
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

    private var helpText: String {
        if !TmuxService.isAvailable { return "서비스 — tmux 설치가 필요합니다" }
        if services.isEmpty { return "서비스 추가 — dev 서버처럼 오래 도는 명령" }
        if deadCount > 0 { return "서비스 \(services.count)개 중 \(deadCount)개가 종료됨 — 클릭해 상세 보기" }
        return "서비스 \(services.count)개 실행 중 — 클릭해 상세 보기 (로그는 ⌘J)"
    }
}
