import SwiftUI

/// 서비스 도크 — 콘텐츠 카드 위에 **겹쳐서** 뜨는 하단 오버레이. [좌: 서비스 목록 | 우: 실제 로그 터미널].
///
/// **왜 오버레이인가.** 레이아웃을 차지하는 도크로 만들면 열고 닫을 때마다 카드가 줄었다 늘고, 그때마다
/// ghostty 그리드가 리플로우된다. 그 비용이 "슬쩍 보고 닫기"를 막아 결국 아무도 안 열게 된다.
/// 겹치면 메인 그리드 리플로우가 0이라 여닫기가 공짜다.
///
/// **왜 2열인가.** web+api+db를 동시에 굴리는 게 흔하다. 로그 하나만 보여주는 서랍은 그 순간 무력해진다.
struct ServiceDock: View {
    let state: AppState
    let project: Project
    let cwd: String?

    @State private var showAdd = false

    /// 카드 높이 대비 도크 높이 — 위쪽 절반 이상은 계속 보여야 에이전트를 감시하면서 로그를 볼 수 있다.
    private let heightRatio: CGFloat = 0.42
    private let listWidth: CGFloat = 180

    private var services: [Service] { state.services(of: project.id) }
    private var selected: Service? {
        services.first { $0.id == state.selectedServiceId } ?? services.first
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    list
                    Rectangle().fill(Color.pBorder).frame(width: 1)
                    detail
                }
                .frame(height: geo.size.height * heightRatio)
                .background(Color.pPanel)
                .overlay(alignment: .top) { Rectangle().fill(Color.pBorder).frame(height: 1) }
            }
        }
        .transition(.move(edge: .bottom))
        .sheet(isPresented: $showAdd) {
            ServiceAddSheet { name, command in
                guard let cwd else { return }
                state.addService(name: name, command: command, to: project.id, cwd: cwd)
            }
        }
    }

    // MARK: 좌 — 서비스 목록

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("서비스").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                }
                .buttonStyle(.plain)
                .help("서비스 추가")
            }
            .padding(.horizontal, Space.panelInset)
            .frame(height: RowHeight.toolbar)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(services) { service in
                        row(service)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: listWidth)
    }

    private func row(_ service: Service) -> some View {
        let status = state.serviceMonitor.states[service.id] ?? .missing
        let isSelected = selected?.id == service.id
        return Button { state.selectedServiceId = service.id } label: {
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(dotColor(status))
                    .frame(width: 6, height: 6)
                Text(service.name)
                    .font(.muxa(.label))
                    .foregroundStyle(isSelected ? Color.pFg : Color.pMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let tail = tail(service, status) {
                    Text(tail)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(dotColor(status))
                }
            }
            .padding(.horizontal, Space.panelInset)
            .frame(height: RowHeight.row)
            .background(isSelected ? Color.pBtnActive.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 우 — 헤더 + 실제 터미널(tmux attach)

    @ViewBuilder
    private var detail: some View {
        if let service = selected {
            VStack(spacing: 0) {
                header(service)
                // 진짜 터미널이다 — Ctrl+C로 죽이고, 스크롤하고, 그 자리에서 디버깅한다.
                TerminalRepresentable(
                    term: state.dockTerm(serviceId: service.id, projectId: project.id, cwd: cwd),
                    onFocus: {}
                )
                .id(service.id) // 서비스를 바꾸면 그 서비스의 터미널로 갈아 끼운다
            }
        } else {
            emptyState
        }
    }

    private func header(_ service: Service) -> some View {
        HStack(spacing: Space.sm) {
            Text(service.name).font(.muxa(.label, weight: .semibold)).foregroundStyle(Color.pFg)
            Text(service.command)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.md)
            // 재시작은 죽었을 때만이 아니라 언제나 유효하다(코드 고치고 다시 띄우기).
            Button {
                guard let cwd else { return }
                state.restartService(service.id, in: project.id, cwd: cwd)
            } label: {
                Image(systemName: "arrow.clockwise").font(.muxa(.micro))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pMuted)
            .help("재시작")

            Button { state.removeService(service.id, from: project.id) } label: {
                Image(systemName: "trash").font(.muxa(.micro))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pMuted)
            .help("서비스 제거 — 등록을 지우고 프로세스도 종료합니다")

            VDivider(height: 12)

            Button { state.closeServiceDock() } label: {
                Image(systemName: "xmark").font(.muxa(.micro))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pMuted)
            .help("도크 닫기 (⌘J) — 프로세스는 계속 돕니다")
        }
        .padding(.horizontal, Space.panelInset)
        .frame(height: RowHeight.toolbar)
        .background(Color.pPanel)
    }

    private var emptyState: some View {
        VStack(spacing: Space.sm) {
            Text("등록된 서비스가 없습니다")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
            Text("dev 서버처럼 오래 도는 명령을 등록하면 여기서 로그를 봅니다.\nmuxa를 꺼도 프로세스는 계속 돕니다.")
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("서비스 추가") { showAdd = true }
                .font(.muxa(.label))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }

    private func dotColor(_ status: ServiceState) -> Color {
        switch status {
        case .running: return .pServiceRunning
        case .exited(let code): return code == 0 ? .pMuted : .pServiceExited
        case .missing: return .pMuted
        }
    }

    private func tail(_ service: Service, _ status: ServiceState) -> String? {
        switch status {
        case .running: return state.serviceMonitor.ports[service.id].map { ":\($0)" }
        case .exited(let code): return code == 0 ? "종료" : "exit \(code)"
        case .missing: return nil
        }
    }
}
