import SwiftUI

/// 서비스 상세 팝오버 — 푸터 칩에 hover하면 열린다(사용량 팝오버와 같은 문법).
///
/// 푸터 칩은 "문제가 있나 없나"만 말한다. **무엇이 왜 그런지는 여기서 말한다** —
/// 서비스별 상태·포트·exit code. 행을 클릭하면 그 서비스의 로그(도크)로 바로 간다.
struct ServicePopover: View {
    let state: AppState
    let project: Project
    /// 행 클릭 → 도크를 그 서비스로 연다.
    let onOpen: (String?) -> Void
    /// "서비스 추가" → 도크를 열면서 추가 시트까지 바로 띄운다.
    let onAdd: () -> Void

    private var services: [Service] { state.services(of: project.id) }
    private let width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            HDivider()
            if !TmuxService.isAvailable {
                // tmux가 없으면 목록이 있을 리 없다 — 왜 못 쓰는지 말하고 안내(도크)로 보낸다.
                hint("tmux가 필요합니다", detail: "dev 서버를 muxa 바깥에서 살려두는 일을 tmux가 맡습니다.")
                Button("설치 안내 보기") { onOpen(nil) }
                    .font(.muxa(.label))
            } else if services.isEmpty {
                // 아무것도 없으면 **추가만** 보여준다 — 빈 목록·빈 상태 문구를 늘어놓지 않는다.
                hint("등록된 서비스가 없습니다",
                     detail: "dev 서버처럼 오래 도는 명령을 등록하면\nmuxa를 꺼도 계속 돕니다.")
                Button("서비스 추가", action: onAdd)
                    .font(.muxa(.label))
            } else {
                ForEach(services) { service in
                    row(service)
                }
            }
        }
        .padding(Space.lg)
        .frame(width: width, alignment: .leading)
        .background(Color.pPanel)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "square.stack.3d.up")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
            Text("서비스")
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
            Spacer(minLength: Space.sm)
            if TmuxService.isAvailable, !services.isEmpty {
                IconButton(icon: "plus", help: "서비스 추가", action: onAdd)
            }
        }
    }

    private func hint(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.muxa(.label)).foregroundStyle(Color.pFg)
            Text(detail)
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 서비스 한 줄 — [● 이름 ··· :3000 / exit 1]. 클릭하면 그 서비스의 로그로 간다.
    private func row(_ service: Service) -> some View {
        let status = state.serviceMonitor.states[service.id] ?? .missing
        return Button { onOpen(service.id) } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: ServiceStatusStyle.glyph(status))
                    .font(.muxa(.micro))
                    .foregroundStyle(ServiceStatusStyle.color(status))
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(service.name)
                        .font(.muxa(.label))
                        .foregroundStyle(Color.pFg)
                    Text(service.command)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Space.sm)
                if let tail = ServiceStatusStyle.tail(status, port: state.serviceMonitor.ports[service.id]) {
                    Text(tail)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(ServiceStatusStyle.color(status))
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("클릭하면 로그를 엽니다")
    }
}
