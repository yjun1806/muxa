import AppKit
import SwiftUI

/// 세션 관리자 — 이 머신의 muxa tmux 세션을 한 표에 모아 보고, 골라 종료한다(YJ-6).
///
/// 활성 상태 보기와 같은 꼴을 의도한다: 정렬 가능한 표, 세그먼트로 나눈 갈래, 하단 요약.
/// **기본 정렬이 메모리 내림차순인 것이 이 화면의 핵심**이다 — 건드리면 안 되는 것이 맨 위로 온다.
struct SessionManagerView: View {
    let monitor: SessionMonitor
    /// 더블클릭한 세션의 탭으로 보낸다(알림 인박스의 클릭과 같은 동선).
    let onReveal: (String) -> Void
    /// 이 앱의 탭이면 세션과 탭을 함께 닫는다. 아니면 false — 호출부가 tmux만 죽인다.
    let onCloseTab: (String) -> Bool

    @State private var filter: SessionFilter = .all
    @State private var search = ""
    @State private var selection: Set<SessionListItem.ID> = []
    @State private var sortOrder = [
        KeyPathComparator(\SessionListItem.weight.footprintBytes, order: .reverse),
    ]

    @State private var preview = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if selectedItem != nil {
                Divider()
                previewPanel
            }
            Divider()
            summaryBar
        }
        .background(Color.pBg)
        // 선택이 바뀔 때만 다시 건다. 그 안에서 주기적으로 갱신하므로 살아있는 세션의 화면이 흐른다.
        .task(id: selectedItem?.id) {
            guard let item = selectedItem else { preview = ""; return }
            while !Task.isCancelled {
                preview = await TmuxService.capture(socket: item.row.socket,
                                                    session: item.row.name, lines: 200)
                try? await Task.sleep(for: SessionMonitor.pollInterval)
            }
        }
    }

    /// 필터 + 검색 + 파괴적 동작.
    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(SessionFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 8)

            TextField("검색", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            // **개수를 라벨에 박는다** — 누르기 전에 무엇이 얼마나 사라지는지 알면 확인창이 필요 없다.
            let sweepable = SessionKillPlan.sweepable(items)
            Button("죽은 pane \(sweepable.count)개 정리") { kill(sweepable) }
                .disabled(sweepable.isEmpty)

            Button(role: .destructive) { killSelected() } label: {
                Label("종료", systemImage: "xmark.circle.fill")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.pPanel)
    }

    /// 선택한 세션의 마지막 화면 — **열기 전에 "어느 세션이었지"를 알려준다.**
    /// 이름(폴더)과 도는 프로세스만으로는 같은 프로젝트의 탭 여럿을 구별할 수 없다.
    private var previewPanel: some View {
        ScrollView {
            Text(preview.isEmpty ? "(화면에 남은 것이 없습니다)" : preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(preview.isEmpty ? Color.pMuted : Color.pFg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 170)
        .background(Color.pPanel)
    }

    @ViewBuilder
    private var content: some View {
        if !TmuxService.isAvailable {
            placeholder("tmux를 찾을 수 없습니다", "muxa의 세션은 tmux에 살아서, 없으면 보여줄 것이 없습니다.")
        } else if !monitor.hasLoaded {
            placeholder("읽는 중…", "이 머신의 muxa 소켓을 훑고 있습니다.")
        } else if items.isEmpty {
            placeholder(search.isEmpty ? "세션이 없습니다" : "검색 결과가 없습니다",
                        search.isEmpty ? "muxa가 만든 tmux 세션이 하나도 없습니다." : "다른 말로 찾아보세요.")
        } else {
            table
        }
    }

    private var table: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("이름", value: \.title) { item in
                HStack(spacing: 6) {
                    Image(systemName: glyph(item))
                        .foregroundStyle(glyphColor(item))
                        // 색·글리프는 VoiceOver에 존재하지 않는다 — 표식으로 말한 것을 말로도 한 번 더.
                        .accessibilityLabel(item.statusText)
                    Text(item.title).lineLimit(1)
                    if item.row.isOrphan {
                        Text("고아")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.pWaiting.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.pWaiting)
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("종류", value: \.kindText) { Text($0.kindText).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 84)

            TableColumn("상태", value: \.statusText) { Text($0.statusText).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 72)

            // 무게 세 열 — 이 화면의 1차 신호. 자릿수가 흔들리지 않게 monospacedDigit.
            TableColumn("메모리", value: \.weight.footprintBytes) { item in
                Text(item.memoryText).monospacedDigit().foregroundStyle(weightTint(item))
            }
            .width(min: 72, ideal: 88)

            TableColumn("CPU %", value: \.weight.cpuPercent) { item in
                Text(item.cpuText).monospacedDigit().foregroundStyle(weightTint(item))
            }
            .width(min: 56, ideal: 64)

            TableColumn("프로세스", value: \.weight.processCount) { item in
                Text("\(item.weight.processCount)").monospacedDigit().foregroundStyle(weightTint(item))
            }
            .width(min: 56, ideal: 64)

            TableColumn("안에 도는 것", value: \.labelsText) { item in
                Text(item.labelsText).lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 200)

            TableColumn("소켓", value: \.socketText) { Text($0.socketText).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 110)

            TableColumn("경로", value: \.row.path) { item in
                Text(item.row.path).lineLimit(1).truncationMode(.head).foregroundStyle(.tertiary)
            }
            .width(min: 120, ideal: 220)
        }
        .tableStyle(.inset)
        // 더블클릭 = 그 터미널로 간다(알림 인박스의 클릭과 같은 동선).
        // 이 앱의 탭이 아니면 라우팅이 조용히 아무것도 하지 않는다 — 다른 인스턴스의 탭을
        // 여기서 앞으로 끌어올 방법은 없다(그 앱이 자기 창을 갖고 있다).
        .contextMenu(forSelectionType: SessionListItem.ID.self) { _ in } primaryAction: { ids in
            guard let id = ids.first, let item = items.first(where: { $0.id == id }) else { return }
            reveal(item)
        }
    }

    private var summaryBar: some View {
        HStack {
            Text(SessionSummary(items: items).text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.pPanel)
    }

    private func placeholder(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 더블클릭 — 그 세션이 있는 곳으로

    /// **어디로 갈 수 있는지는 누가 보고 있느냐에 달렸다.**
    ///  - 이 앱의 탭이면 그 탭으로(알림 인박스 클릭과 같은 동선).
    ///  - 다른 muxa 인스턴스면 **그 앱을 앞으로** 가져온다. 어느 탭인지는 그 앱의 상태라 우리가 모른다 —
    ///    거기까지가 우리가 할 수 있는 전부다.
    ///  - 붙은 곳이 없으면(분리됨·외부) 갈 곳이 없다. 대신 아래 미리보기가 이미 그 세션의 마지막
    ///    화면을 보여주고 있으므로, 더블클릭이 아무 일도 안 하는 것처럼 보이지는 않는다.
    private func reveal(_ item: SessionListItem) {
        switch item.row.attachment {
        case .thisApp:
            onReveal(item.row.name)
        case .otherApp(_, let pid):
            NSRunningApplication(processIdentifier: pid)?.activate()
        case .external, .detached:
            break
        }
    }

    // MARK: 종료 — 이 창에서 유일하게 파괴적인 동작

    private func killSelected() {
        kill(items.filter { selection.contains($0.id) })
    }

    /// 판정은 `SessionKillPlan`(순수)에 맡기고 여기서는 묻고 죽이기만 한다.
    private func kill(_ targets: [SessionListItem]) {
        guard !targets.isEmpty else { return }
        if let warning = SessionKillPlan.warning(for: targets, ownSocket: TmuxService.socket),
           !confirm(warning) { return }
        Task {
            for target in targets {
                // **이 앱의 탭이면 탭까지 닫는다.** tmux 세션만 죽이면 attach가 끝난 뒤 바깥 셸이
                // 남아 탭이 그대로 보인다 — 사용자에게는 "종료를 눌렀는데 안 꺼진" 화면이다.
                // muxa의 기존 '완전 종료' 경로가 세션 kill·탭 닫기·내부 맵 정리를 한꺼번에 한다.
                if onCloseTab(target.row.name) { continue }
                await TmuxService.kill(socket: target.row.socket, session: target.row.name)
            }
            selection.subtract(targets.map(\.id))
            // 폴링을 기다리지 않고 즉시 다시 훑는다 — 누른 것이 사라지는 게 바로 보여야 한다.
            await monitor.refresh()
        }
    }

    private func confirm(_ warning: SessionKillPlan.Warning) -> Bool {
        let alert = NSAlert()
        alert.messageText = warning.title
        alert.informativeText = warning.detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")
        // 기본 버튼은 취소다 — Enter를 습관적으로 눌러 돌고 있는 작업을 죽이지 않게.
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: 파생

    private var selectedItem: SessionListItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return items.first { $0.id == id }
    }

    private var items: [SessionListItem] {
        monitor.rows
            .map { SessionListItem(row: $0, weight: monitor.weight(of: $0)) }
            .filter { filter.matches($0) && $0.matches(search: search) }
            .sorted(using: sortOrder)
    }

    /// 상태 글리프 — 서비스 축의 어휘를 따른다(`ServiceStatusStyle`). **색만으로 구분하지 않는다.**
    ///
    /// 숨은 터미널만 모양이 다르다 — 이 창이 찾아야 할 것이라 훑을 때 먼저 걸려야 한다.
    /// **스크립트·서비스의 분리는 여기 들지 않는다**: 백그라운드가 그들의 정상이라, 눈길을 끌면
    /// 멀쩡히 도는 dev 서버가 문제처럼 보인다(`SessionListItem.isHidden`).
    private func glyph(_ item: SessionListItem) -> String {
        if item.row.isDead { return "stop.circle" }
        if item.isHidden { return "eye.slash.circle.fill" }
        switch item.row.attachment {
        case .otherApp: return "play.circle"
        case .external: return "terminal"
        // 내 탭, 그리고 백그라운드로 도는 스크립트·서비스.
        case .thisApp, .detached: return "play.circle.fill"
        }
    }

    private func glyphColor(_ item: SessionListItem) -> Color {
        if item.row.isDead { return .pMuted }
        // 주의를 끈다(경고는 아니다 — 일부러 남긴 세션일 수도 있다).
        if item.isHidden { return .pWaiting }
        switch item.row.attachment {
        case .thisApp, .detached: return .pServiceRunning
        case .otherApp, .external: return .pDone
        }
    }

    /// **비어 있는 세션은 흐리게 쓴다.** 표를 훑을 때 "지워도 되는 것"이 먼저 눈에서 빠져야 한다.
    private func weightTint(_ item: SessionListItem) -> Color {
        item.weight.processCount == 0 ? .pMuted : .pFg
    }
}
