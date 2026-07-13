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
            // cwd를 넘겨 package.json 스크립트를 찾게 한다(직접 입력도 그대로 가능).
            ServiceAddSheet(cwd: cwd) { name, command in
                guard let cwd else { return }
                state.addService(name: name, command: command, to: project.id, cwd: cwd)
            }
        }
        // 팝오버에서 "서비스 추가"로 들어왔으면 시트를 바로 띄운다(두 번 클릭 방지). 요청은 원샷.
        .onChange(of: state.serviceAddRequested, initial: true) { _, requested in
            guard requested else { return }
            state.serviceAddRequested = false
            showAdd = true
        }
    }

    // MARK: 좌 — 서비스 목록

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Text("서비스").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.xs)
                // tmux가 없으면 추가해봐야 돌지 않는다 — 등록 버튼을 감추고 우측 설치 안내로 유도한다.
                if TmuxService.isAvailable {
                    IconButton(icon: "plus", help: "서비스 추가") { showAdd = true }
                }
                // 닫기는 **여기에도** 둔다 — 우측 헤더는 선택된 서비스가 있을 때만 뜨므로,
                // 서비스가 하나도 없으면 도크를 닫을 방법이 사라진다.
                IconButton(icon: "xmark", help: "도크 닫기 (⌘J) — 프로세스는 계속 돕니다") {
                    state.closeServiceDock()
                }
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
        if !TmuxService.isAvailable {
            // tmux가 없으면 기능을 숨기는 대신 **왜 없는지 말하고 설치를 돕는다**.
            ServiceSetupView(state: state) { command in
                state.activeStore?.injectToTerminal(command) ?? false
            }
        } else if let service = selected {
            VStack(spacing: 0) {
                header(service)
                if isDead(service) {
                    // 죽었으면 읽기 전용 로그 — 터미널을 붙이지 않는다(ServiceLogView 주석).
                    ServiceLogView(projectId: project.id, serviceId: service.id,
                                   reloadToken: "\(service.id)|\(state.serviceRestartSeq)")
                } else {
                    // 살아있으면 **진짜 터미널**(tmux attach) — Ctrl+C로 죽이고, 스크롤하고,
                    // 그 자리에서 디버깅한다.
                    TerminalRepresentable(
                        term: state.dockTerm(serviceId: service.id, projectId: project.id, cwd: cwd),
                        onFocus: {}
                    )
                    .id(service.id) // 서비스를 바꾸면 그 서비스의 터미널로 갈아 끼운다
                }
            }
        } else {
            emptyState
        }
    }

    /// 도크 헤더 — 이름·명령·조작 버튼.
    ///
    /// 버튼은 `IconButton`(14x14 고정)을 쓰고 명령 텍스트의 레이아웃 우선순위를 낮춘다.
    /// 크기가 유연한 버튼을 쓰면 HStack이 공간을 배분할 때 **명령 텍스트가 공간을 먼저 가져가고
    /// 버튼이 0폭으로 압축돼 사라진다** — 닫기 버튼이 사라져서 도크를 닫을 수 없게 된다.
    private func header(_ service: Service) -> some View {
        HStack(spacing: Space.sm) {
            Text(service.name)
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .fixedSize()
            Text(service.command)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1) // 자리가 모자라면 여기부터 줄인다(버튼은 끝까지 남는다)
            Spacer(minLength: Space.sm)
            // 재시작은 죽었을 때만이 아니라 언제나 유효하다(코드 고치고 다시 띄우기).
            IconButton(icon: "arrow.clockwise", help: "재시작") {
                guard let cwd else { return }
                state.restartService(service.id, in: project.id, cwd: cwd)
            }
            IconButton(icon: "trash", help: "서비스 제거 — 등록을 지우고 프로세스도 종료합니다") {
                state.removeService(service.id, from: project.id)
            }
            VDivider(height: 12)
            IconButton(icon: "xmark", help: "도크 닫기 (⌘J) — 프로세스는 계속 돕니다") {
                state.closeServiceDock()
            }
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

    /// 죽었나 — tmux가 진실 원천이다. 아직 상태를 모르면(missing) 살아있다고 보고 attach를 시도한다
    /// (폴링 첫 바퀴 전이라도 도크가 빈 화면으로 뜨지 않게).
    private func isDead(_ service: Service) -> Bool {
        if case .exited = state.serviceMonitor.states[service.id] ?? .missing { return true }
        return false
    }

    // 색·글리프·꼬리표 규칙은 ServiceStatusStyle 한 곳에 있다(칩·팝오버와 같은 규칙을 쓰려고).
    private func dotColor(_ status: ServiceState) -> Color { ServiceStatusStyle.color(status) }

    private func tail(_ service: Service, _ status: ServiceState) -> String? {
        ServiceStatusStyle.tail(status, port: state.serviceMonitor.ports[service.id])
    }
}
