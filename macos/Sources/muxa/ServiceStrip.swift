import SwiftUI

/// 푸터의 서비스 칩 — **접혀 있어도 보이는 유일한 상시 신호**.
///
/// 이 기능의 요구는 "접을 수 있어야 하지만 숨어서 못 알아채면 안 된다"였다. 도크는 접히므로,
/// 접힌 상태에서 상태를 말해주는 건 이 칩뿐이다. 그래서 점 하나가 아니라 **이름·상태·포트·exit code**까지
/// 싣는다 — 점만 있으면 "뭔가 빨간데 뭐가 왜 죽었지"를 모른다.
struct ServiceStrip: View {
    let state: AppState
    let project: Project
    let cwd: String?

    private var services: [Service] { state.services(of: project.id) }

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            if TmuxService.isAvailable {
                ForEach(services) { service in
                    chip(service)
                }
                addButton
            } else {
                // tmux가 없어도 **완전히 숨기지는 않는다.** 숨기면 사용자는 이 기능이 있는지조차 모른다.
                // 조용한 진입점 하나만 남기고, 왜 못 쓰는지와 설치 방법은 도크가 설명한다.
                setupHint
            }
        }
    }

    /// tmux 미설치 상태의 진입점 — 눈에 거슬리지 않게 흐리게 두되, 누르면 설치 안내가 열린다.
    private var setupHint: some View {
        Button { state.openServiceDock(serviceId: nil) } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: "shippingbox").font(.muxa(.micro))
                Text("서비스").font(.muxa(.label))
            }
            .foregroundStyle(Color.pMuted.opacity(0.6))
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("dev 서버 같은 장수 프로세스를 등록합니다 — tmux 설치가 필요합니다")
    }

    /// 서비스 칩 — [● 이름 :포트] / [⛔ 이름 exit 1]. 클릭하면 도크가 그 서비스로 열린다.
    private func chip(_ service: Service) -> some View {
        let status = state.serviceMonitor.states[service.id] ?? .missing
        return Button { state.openServiceDock(serviceId: service.id) } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                // 색만으로 구분하지 않는다(색맹 안전) — 죽으면 글리프 자체가 바뀐다.
                Image(systemName: glyph(status))
                    .font(.muxa(.micro))
                    .foregroundStyle(color(status))
                Text(service.name)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                if let detail = detail(service, status) {
                    Text(detail)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(color(status))
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(Color.pBtnHover.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .help(helpText(service, status))
    }

    private var addButton: some View {
        Button { state.openServiceDock(serviceId: nil) } label: {
            Image(systemName: "plus")
                .font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
                .frame(width: 18, height: RowHeight.tight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("서비스 추가 — dev 서버처럼 오래 도는 명령")
    }

    private func glyph(_ status: ServiceState) -> String {
        switch status {
        case .running: return "circle.fill"
        case .exited(let code): return code == 0 ? "stop.circle" : "exclamationmark.triangle.fill"
        case .missing: return "circle.dotted"
        }
    }

    private func color(_ status: ServiceState) -> Color {
        switch status {
        case .running: return .pServiceRunning
        case .exited(let code): return code == 0 ? .pMuted : .pServiceExited
        case .missing: return .pMuted
        }
    }

    /// 칩의 꼬리표 — 포트(있으면)나 exit code. 포트를 못 뽑았으면 아무것도 붙이지 않는다(지어내지 않는다).
    private func detail(_ service: Service, _ status: ServiceState) -> String? {
        switch status {
        case .running: return state.serviceMonitor.ports[service.id].map { ":\($0)" }
        case .exited(let code): return code == 0 ? nil : "exit \(code)"
        case .missing: return nil
        }
    }

    private func helpText(_ service: Service, _ status: ServiceState) -> String {
        switch status {
        case .running: return "\(service.name) 실행 중 — \(service.command)"
        case .exited(let code):
            return code == 0 ? "\(service.name) 종료됨 — 클릭해 로그 보기"
                             : "\(service.name)이 exit \(code)로 죽었습니다 — 클릭해 로그 보기"
        case .missing: return "\(service.name) — 아직 시작되지 않음"
        }
    }
}
