import Bonsplit
import SwiftUI

/// **에이전트 패널** — 어느 세션이 무엇을 만졌나(YJ-7). Git 패널이 *리포*를 주제로 말하는 것과
/// 갈라, 이 패널은 *귀속*을 말한다.
///
/// controlled 뷰다 — 상태는 `TerminalStore`가 소유하고 여기는 값·클로저만 받아 그린다
/// (`GitPanel`과 같은 문법).
///
/// **채널이 셋이고 각각 한 가지 일만 한다**: 채움 = 자리(그룹 = 보고 있는 세션 / 행 = 선택),
/// 굵기 = 안 봤음, 글리프 = git 상태. 겹치면 "굵은 게 안 본 건지 선택된 건지"를 매번 되짚게 된다.
struct AgentPanel: View {
    let store: TerminalStore
    /// 저장소 루트(절대) — 수집 경로는 절대라, git status의 상대경로를 여기에 붙여 맞춘다.
    /// nil이면 아직 폴더가 없는 워크스페이스다(`GitPanel`과 같은 계약).
    let dir: String?
    /// 파일 diff 열기 — 이 패널이 여는 유일한 대상이다(일반 뷰어 버튼은 없다).
    var onOpenDiff: (GitDiffTarget) -> Void
    /// 리포의 진실로 보내기 — 귀속 안 된 변경은 Git 패널이 답한다.
    var onOpenGitPanel: () -> Void

    /// 절대경로 → git 상태 문자. 30초 tick과 함께 갱신한다.
    @State private var status: [String: Character] = [:]
    @State private var mtimes: [String: Date] = [:]
    /// 수집에 귀속되지 않은 변경 수 — 훅이 못 보는 `Bash` 경유 변경(sed·스크립트·git mv).
    @State private var unattributed = 0
    @State private var collapsed: Set<String> = []
    @State private var tick = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            HDivider()
            if groups.isEmpty {
                empty
            } else {
                ScrollView { body_ }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pPanel)
        .task(id: dir) { await refresh() }
        // 수집이 바뀌면(에이전트가 또 만졌다) 상태·mtime을 다시 읽는다.
        .onChange(of: store.agentChanges.count) { _, _ in Task { await refresh() } }
        .tick(every: 30, into: $tick)
        .onChange(of: tick) { _, _ in Task { await refresh() } }
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: Space.sm) {
            ClaudeMark(size: IconSize.inlineMark)
            Text("에이전트").font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
            Spacer(minLength: 0)
            IconButton(icon: "arrow.clockwise", help: "새로 고치기") { Task { await refresh() } }
        }
        .padding(.horizontal, Space.panelInset)
        .frame(height: RowHeight.header)
    }

    /// 훅이 없거나 에이전트가 아무것도 안 만졌다 — 죽은 화면 대신 왜 비었는지 말한다.
    private var empty: some View {
        EmptyState(icon: "square.dashed",
                   title: "아직 만진 파일이 없습니다",
                   subtitle: "claude가 파일을 편집하면 세션별로 여기 모입니다",
                   compact: true) { EmptyView() }
    }

    @ViewBuilder
    private var body_: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            ForEach(groups, id: \.key) { item in
                group(item)
            }
            if unattributed > 0 { residual }
        }
        .padding(.vertical, Space.sm)
    }

    // MARK: 그룹 = 세션 하나

    @ViewBuilder
    private func group(_ item: GroupItem) -> some View {
        let focused = item.tabId == store.currentTabId
        let open = !collapsed.contains(item.key)
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(item, focused: focused, open: open)
            if open {
                // **보고 있는 그룹 안에서는 레인 면을 그리지 않는다** — 강조 면이 이미
                // "한 묶음"을 말하므로 같은 말을 두 번 하지 않는다.
                rows(item)
                    .padding(Space.xs)
                    .background {
                        if !focused {
                            RoundedRectangle(cornerRadius: Radius.lg).fill(Color.pLane)
                        }
                    }
            }
        }
        // 보고 있는 세션 = 무채 채움 **한 단**. 선택 채움(btnActive)을 쓰면 그 안의 선택 행이
        // 사라지므로 한 칸 아래(btnHover)를 쓴다 — panel → lane → 보는 그룹 → 선택 행.
        .padding(.bottom, focused ? Space.xs : 0)
        .background {
            if focused {
                RoundedRectangle(cornerRadius: Radius.lg).fill(Color.pBtnHover)
            }
        }
        .padding(.horizontal, Space.xs)
    }

    @ViewBuilder
    private func groupHeader(_ item: GroupItem, focused: Bool, open: Bool) -> some View {
        HStack(spacing: Space.sm) {
            ClaudeMark(size: IconSize.statusSlot)
            Text(item.title)
                .font(.muxa(.body, weight: item.group.unreadCount > 0 ? .bold : .medium))
                // 전부 봤으면 제목이 흐려진다 — 훑을 때 굵은 제목만 남는다.
                .foregroundStyle(item.group.unreadCount > 0 ? Color.pFg : Color.pMuted)
                .lineLimit(1).truncationMode(.tail)
            // 안 본 개수 롤업 — **0이면 배지 자체가 없다**(0이면 숨김).
            if item.group.unreadCount > 0 {
                Text("\(item.group.unreadCount)")
                    .font(.muxaMono(.micro, weight: .bold))
                    .foregroundStyle(Color.pBg)
                    .padding(.horizontal, Space.xs)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.pFg))
            }
            Spacer(minLength: 0)
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        // 행 클릭 = 펼침/접힘 (커밋 행과 같은 제스처 — 훑기와 정독이 제스처를 공유하지 않는다).
        .onTapGesture { toggle(item.key) }
    }

    @ViewBuilder
    private func rows(_ item: GroupItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(item.group.rows) { row in
                fileRow(row, base: item.group.baseline, tabId: item.tabId)
            }
            if item.group.hiddenCount > 0 {
                tail("그 외 \(item.group.hiddenCount)개")
            }
            // 접은 것과 **애초에 못 받은 것**은 다른 사건이라 따로 말한다.
            if item.group.truncatedCount > 0 {
                tail("오래된 항목 \(item.group.truncatedCount)건은 기록이 잘렸습니다")
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ row: AgentChangeRow, base: String?, tabId: TabID) -> some View {
        let rel = relative(row.path)
        HStack(spacing: Space.sm) {
            switch row.mark {
            case .git(let code):
                GitStatusBadge(code: code)
            case .committed:
                // git이 조용한데 디스크는 바뀌었다 = 커밋됐다. 무채 — git 축의 색을 빌리지 않는다.
                Image(systemName: "checkmark")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusSlot)
            }
            // 굵기·색이 **안 봤음** 전용 채널이다(선택은 채움이 말한다).
            GitFileLabel(path: rel,
                         weight: row.isUnread ? .semibold : .regular,
                         tone: row.isUnread ? Color.pFg : Color.pMuted)
            if case .committed = row.mark {
                Text("커밋됨").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            GitFileTime(mtime: row.mtime, now: tick)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        .modifier(ListRowFill())
        .onTapGesture { open(rel, base: base, tabId: tabId) }
    }

    private func tail(_ text: String) -> some View {
        Text(text)
            .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight, alignment: .leading)
    }

    /// 귀속 안 된 변경 — 이 패널이 **완전성을 참칭하지 않게** 하는 유일한 방어다.
    /// 훅은 `Bash`(sed·스크립트·git mv) 경유 변경을 원리상 못 본다. Git 패널과 나란히 있었다면
    /// 리포의 진실이 늘 옆에 보였는데, 패널을 가른 대가로 그 방어가 사라졌다.
    private var residual: some View {
        HStack(spacing: Space.sm) {
            Text("귀속 안 된 변경 \(unattributed)건")
                .font(.muxa(.label)).foregroundStyle(Color.pMuted)
            Spacer(minLength: 0)
            Text("Git 패널 →").font(.muxa(.caption, weight: .semibold)).foregroundStyle(Color.pBrand)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .overlay(alignment: .top) { HDivider() }
        .contentShape(Rectangle())
        .onTapGesture { onOpenGitPanel() }
        .padding(.horizontal, Space.xs)
    }

    // MARK: 파생

    /// 화면에 세울 그룹 하나 — 탭 하나에 대응한다.
    struct GroupItem {
        let key: String
        let tabId: TabID
        let title: String
        let group: AgentChangeGroup
        /// 이 그룹의 diff 기준 리비전. 없으면 열 때 HEAD로 떨어진다.
        var baseline: String? { group.baseline }
    }

    /// 보고 있는 세션을 **맨 위**에 세운다 — 목록에서 찾는 데 시간이 들면 안 된다.
    private var groups: [GroupItem] {
        store.agentChanges.compactMap { tabId, set -> GroupItem? in
            let g = AgentChangeDisplay.group(from: set, status: status, mtimes: mtimes)
            guard !g.rows.isEmpty else { return nil } // 0이면 그룹째 렌더하지 않는다
            return GroupItem(key: tabId.uuid.uuidString, tabId: tabId,
                             title: g.title ?? store.tabTitle(tabId), group: g)
        }
        .sorted { lhs, rhs in
            let l = lhs.tabId == store.currentTabId, r = rhs.tabId == store.currentTabId
            if l != r { return l }
            return lhs.title < rhs.title
        }
    }

    private func toggle(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    /// 저장소 루트 기준 상대경로 — 행 라벨·diff 인자가 쓴다(git은 상대경로로 말한다).
    private func relative(_ absolute: String) -> String {
        guard let dir else { return absolute }
        let root = dir.hasSuffix("/") ? dir : dir + "/"
        return absolute.hasPrefix(root) ? String(absolute.dropFirst(root.count)) : absolute
    }

    private func open(_ rel: String, base: String?, tabId: TabID) {
        // 기준선이 없으면(아직 못 읽었다) HEAD로 떨어진다 — 열리지 않는 행을 만들지 않는다.
        onOpenDiff(.baselineFile(base: base ?? "HEAD", path: rel))
        // "봤음"은 **그 그룹의 탭**에 찍는다 — 포커스 탭에 찍으면 남의 기록을 건드린다.
        guard let dir else { return }
        store.markAgentChangeSeen(tabId: tabId,
                                  path: (dir as NSString).appendingPathComponent(rel))
    }

    // MARK: 새로 고치기

    /// git status·mtime을 한 번에 읽어 절대경로 키로 맞춘다. 수집 경로는 절대, git은 상대라
    /// 여기서 맞추지 않으면 **모든 행이 "흔적 없음"으로 억제된다**.
    private func refresh() async {
        let paths = Set(store.agentChanges.values.flatMap { $0.entries.keys })
        guard let dir else { status = [:]; mtimes = [:]; unattributed = 0; return }
        let st = await GitService.status(in: dir)

        var map: [String: Character] = [:]
        for change in st?.changes ?? [] {
            let abs = (dir as NSString).appendingPathComponent(change.opPath)
            // 인덱스·워크트리 중 의미 있는 쪽 — 미추적은 `?`.
            map[abs] = change.isUntracked ? "?" : (change.worktree != " " ? change.worktree : change.index)
        }
        status = map

        var times: [String: Date] = [:]
        for path in paths {
            times[path] = (try? FileManager.default
                .attributesOfItem(atPath: path)[.modificationDate]) as? Date
        }
        mtimes = times

        // 귀속 = 수집된 경로. git이 아는 변경에서 그걸 빼면 훅이 못 본 것만 남는다.
        unattributed = map.keys.filter { !paths.contains($0) }.count
    }
}
