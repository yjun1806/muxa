import SwiftUI

/// 서비스 상세 팝오버 — 푸터 칩에 hover하면 열린다(사용량 팝오버와 같은 문법).
///
/// **창 전체의 서비스를 보여준다.** 서비스는 프로젝트 소속이지만, 사용자가 알아야 하는 건
/// "지금 이 프로젝트"가 아니라 **어디서 뭐가 도는가**다. 다른 워크스페이스의 dev 서버가 죽었는데
/// 거기 들어가야만 알 수 있다면 알림으로서 실패다.
///
/// 지금 프로젝트를 맨 위에 두고 나머지는 프로젝트별로 묶는다. 어느 행이든 클릭하면 그리로 데려간다.
struct ServicePopover: View {
    let state: AppState
    /// 지금 보고 있는 프로젝트 — 맨 위로 올리고 "현재" 표시를 단다.
    let currentProjectId: String
    /// 행 클릭 → 그 서비스가 있는 곳으로 이동 + 로그 열기.
    let onReveal: (LocatedService) -> Void
    /// "서비스 추가" → 도크를 열면서 추가 시트까지 바로 띄운다.
    let onAdd: () -> Void

    private let width: CGFloat = 300

    /// 프로젝트별로 묶고, 현재 프로젝트를 맨 앞에. (프로젝트 안에서는 선언 순서 유지.)
    private var groups: [(projectId: String, title: String, services: [LocatedService])] {
        var order: [String] = []
        var byProject: [String: [LocatedService]] = [:]
        for item in state.allLocatedServices {
            if byProject[item.projectId] == nil { order.append(item.projectId) }
            byProject[item.projectId, default: []].append(item)
        }
        return order
            .sorted { a, _ in a == currentProjectId } // 현재 프로젝트를 맨 앞으로
            .compactMap { pid in
                guard let items = byProject[pid], let first = items.first else { return nil }
                // 워크스페이스가 여럿이면 어느 워크스페이스인지도 밝힌다("front › 웹").
                let title = state.workspaces.count > 1
                    ? "\(first.workspaceName) › \(first.projectName)"
                    : first.projectName
                return (pid, title, items)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            HDivider()
            if !TmuxService.isAvailable {
                hint("tmux가 필요합니다", detail: "dev 서버를 muxa 바깥에서 살려두는 일을 tmux가 맡습니다.")
                Button("설치 안내 보기", action: onAdd)
                    .font(.muxa(.label))
            } else if groups.isEmpty {
                // 아무것도 없으면 **추가만** 보여준다 — 빈 목록을 늘어놓지 않는다.
                hint("등록된 서비스가 없습니다",
                     detail: "dev 서버처럼 오래 도는 명령을 등록하면\nmuxa를 꺼도 계속 돕니다.")
                Button("서비스 추가", action: onAdd)
                    .font(.muxa(.label))
            } else {
                ForEach(groups, id: \.projectId) { group in
                    section(group)
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
            if TmuxService.isAvailable, !groups.isEmpty {
                IconButton(icon: "plus", help: "서비스 추가", action: onAdd)
            }
        }
    }

    /// 프로젝트 한 묶음 — 어느 프로젝트 것인지 밝히고 그 아래 서비스를 편다.
    private func section(_ group: (projectId: String, title: String, services: [LocatedService])) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.xs) {
                Text(group.title)
                    .font(.muxa(.caption, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                if group.projectId == currentProjectId {
                    Text("현재")
                        .font(.muxa(.nano))
                        .foregroundStyle(Color.pMuted.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.sm)

            ForEach(group.services) { item in
                row(item)
            }
        }
    }

    /// 서비스 한 줄 — [● 이름 · 명령 ··· :3000 / exit 1]. 클릭하면 **그 프로젝트로 데려가서** 로그를 연다.
    private func row(_ item: LocatedService) -> some View {
        let status = state.serviceMonitor.states[item.service.id] ?? .missing
        return Button { onReveal(item) } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: ServiceStatusStyle.glyph(status))
                    .font(.muxa(.micro))
                    .foregroundStyle(ServiceStatusStyle.color(status))
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.service.name)
                        .font(.muxa(.label))
                        .foregroundStyle(Color.pFg)
                    Text(item.service.command)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Space.sm)
                if let tail = ServiceStatusStyle.tail(status, port: state.serviceMonitor.ports[item.service.id]) {
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
        .help(item.projectId == currentProjectId
              ? "클릭하면 로그를 엽니다"
              : "클릭하면 \(item.projectName)(으)로 이동해 로그를 엽니다")
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
}
