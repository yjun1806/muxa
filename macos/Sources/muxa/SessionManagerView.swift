import AppKit
import SwiftUI

/// 세션 관리자 — 이 머신의 muxa tmux 세션을 한 표에 모아 보고, 골라 종료한다(YJ-6).
///
/// 활성 상태 보기와 같은 꼴을 의도한다: 정렬 가능한 표, 세그먼트로 나눈 갈래, 하단 요약.
/// **기본 정렬이 메모리 내림차순인 것이 이 화면의 핵심**이다 — 건드리면 안 되는 것이 맨 위로 온다.
struct SessionManagerView: View {
    let monitor: SessionMonitor

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

    /// 상태 글리프 — 서비스 축의 어휘를 그대로 쓴다(`ServiceStatusStyle`). 색만으로 구분하지 않는다.
    private func glyph(_ item: SessionListItem) -> String {
        if item.row.isDead { return "stop.circle" }
        return item.row.isAttached ? "play.circle.fill" : "circle.fill"
    }

    private func glyphColor(_ item: SessionListItem) -> Color {
        if item.row.isDead { return .pMuted }
        return item.row.isAttached ? .pServiceRunning : .pDone
    }

    /// **비어 있는 세션은 흐리게 쓴다.** 표를 훑을 때 "지워도 되는 것"이 먼저 눈에서 빠져야 한다.
    private func weightTint(_ item: SessionListItem) -> Color {
        item.weight.processCount == 0 ? .pMuted : .pFg
    }
}
