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
    /// 참고 목록 열기 — 패널엔 한 줄만 두고 목록은 탭으로 보낸다(읽기가 편집을 압도한다).
    var onOpenReferences: (TabID, String) -> Void
    /// 그 세션의 터미널 탭으로 이동 — 패널이 곧 **세션 스위처**다.
    /// 접힘 상태를 따로 두지 않는다: **포커스된 세션이 열린 세션**이므로 이동이 곧 펼침이다.
    var onFocusSession: (TabID) -> Void

    /// 절대경로 → git 상태 문자. 30초 tick과 함께 갱신한다.
    @State private var status: [String: Character] = [:]
    @State private var mtimes: [String: Date] = [:]
    /// **이 패널이 모르는** 변경 수 — git은 아는데 수집엔 없는 것.
    /// 훅이 못 보는 `Bash` 경유 에이전트 변경(sed·스크립트·git mv)이 여기 들어오지만,
    /// **사용자가 직접 고친 파일도 함께 들어온다** — 그래서 "에이전트가 몰래 한 것"이라고
    /// 말하지 않는다. 이 패널의 목록이 전부가 아님을 알리는 게 이 행의 일이다.
    @State private var unknownToPanel = 0
    // 접힘은 **AppState가 소유**한다(영속) — 뷰 로컬 @State면 패널을 닫았다 열 때마다
    // 전부 다시 펼쳐진다. 사이드바가 같은 실수를 이미 겪고 고쳤다(`SidebarProjectRow` 주석).
    @State private var tick = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            // **잔차 행은 groups와 독립이다.** 예전엔 `groupList` 안에 있어서, 훅 추적 기록이 0인데
            // 저장소는 dirty한 상태(첫 사용에서 가장 흔하다)에서 "만진 파일이 없습니다"만 뜨고
            // 실제 변경 N건이 통째로 숨었다 — 완전성 참칭을 막는 유일한 방어가 정작 가장 필요한
            // 순간에 죽는 경로였다.
            if groups.isEmpty && unknownToPanel == 0 {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.groupGap) {
                        if groups.isEmpty { emptyInline }
                        groupList
                        if unknownToPanel > 0 {
                            HDivider().padding(.horizontal, Space.xs).padding(.top, Space.sm)
                            residual
                        }
                    }
                    .padding(.vertical, Space.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 탐색기·Git은 `panel`(크롬)인데 여기는 **`bg`(콘텐츠)**를 쓴다 — 훑어 읽는 목록이라
        // 밝은 면이 낫고, 그룹 강조(`btnHover`)와의 대비도 커진다.
        .background(Color.pBg)
        .task(id: dir) {
            // 재시작 후 지속 세션의 기록은 파일엔 있어도 메모리엔 없다 — 한 번 올린다(②).
            store.hydrateAgentChangesForLiveTabs()
            await refresh()
        }
        // 수집이 바뀌면(에이전트가 또 만졌다) 상태·mtime을 다시 읽는다.
        // **리비전을 본다** — 개수는 기존 탭에 파일이 하나 더 붙는 걸 놓친다(①).
        .onChange(of: store.agentChangesRevision) { _, _ in Task { await refresh() } }
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
        .panelBar(height: RowHeight.panelHeader) // 아래 구분선까지 합쳐 칸 탭바와 같은 높이
    }

    /// 훅이 없거나 에이전트가 아무것도 안 만졌다 — 죽은 화면 대신 왜 비었는지 말한다.
    private var empty: some View {
        EmptyState(icon: "square.dashed",
                   title: "아직 만진 파일이 없습니다",
                   subtitle: "claude가 파일을 편집하거나 읽으면 세션별로 여기 모입니다",
                   compact: true) { EmptyView() }
    }

    @ViewBuilder
    private var groupList: some View {
        ForEach(groups, id: \.key) { item in
            group(item)
        }
    }

    /// 수집 기록은 없는데 잔차는 있는 상태 — "없다"가 아니라 **"이 패널이 못 봤다"**라고 말한다.
    private var emptyInline: some View {
        Text("이 세션에서 추적된 편집이 없습니다")
            .font(.muxa(.label)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.panelInset)
            .frame(height: RowHeight.row, alignment: .leading)
    }

    // MARK: 그룹 = 세션 하나

    @ViewBuilder
    private func group(_ item: GroupItem) -> some View {
        // **아코디언 하나만** — 이 저장소가 같은 폭에서 이미 내린 결정이다
        // (`DESIGN.md:365` "폭이 180pt까지 좁아지면 여럿 펼침이 위계를 무너뜨린다").
        // 열린 것이 곧 활성이라 강조를 위한 채움·색이 따로 필요 없다.
        let open = item.key == openKey
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(item, open: open)
            if open {
                // 자식은 **늘** 레인 위에 앉는다 — 소속을 그리는 건 레인의 일이고,
                // 포커스는 헤더 행이 말한다. 두 역할을 섞지 않는다.
                rows(item)
                    .padding(Space.xs)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.lg).fill(Color.pLane)
                    }
            }
        }
        .padding(.horizontal, Space.xs)
    }

    @ViewBuilder
    private func groupHeader(_ item: GroupItem, open: Bool) -> some View {
        HStack(spacing: Space.sm) {
            // 마크는 **정체성(WHO)**이라 상태로 쓰지 않는다(임의 opacity 곱도 금지 — DESIGN §2).
            // 지금 보고 있는 세션은 "열려 있다"가 말하므로 마크를 건드릴 이유가 없다.
            ClaudeMark(size: IconSize.statusSlot)
            Text(item.title)
                .font(.muxa(.body, weight: open ? .semibold : .regular))
                .foregroundStyle(open ? Color.pFg : Color.pMuted)
                .lineLimit(1).truncationMode(.tail)
            // 접힌 세션은 내용이 안 보이므로 **숫자가 유일한 단서**다. 펼쳐진 쪽은 행들이 곧 개수라
            // 배지가 같은 말의 세 번째 반복이 된다 — 그래서 접혔을 때만.
            if !open, item.group.unreadCount > 0 {
                CountBadge(count: item.group.unreadCount)
            }
            Spacer(minLength: 0)
            // 접힌 세션은 "누르면 간다"는 뜻이므로 이동 어포던스(›)를 쓴다.
            // 열린 것엔 아무것도 안 붙인다 — 접을 수 있는 게 아니라 지금 보고 있는 것이다.
            if !open {
                Image(systemName: "chevron.right")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
            }
        }
        // 인셋 10 — 헤더 제목(4+10+12+6=32)과 파일명(4+레인4+6+12+6=32)이 같은 세로선에서 시작한다.
        // 6이면 4pt 어긋나 두 단이 미묘하게 삐뚤어 보인다(사이드바는 이 산수를 맞춰 뒀다).
        .padding(.horizontal, Space.panelInset)
        .frame(height: RowHeight.toolbar) // **고정** — 가변이면 탭을 바꿀 때마다 아래 그룹이 밀린다
        // **채움을 쓰지 않는다.** 열려 있다는 사실이 곧 "지금 이 세션"이다 —
        // 아래에 파일이 달린 그룹은 하나뿐이라 색·채움으로 덧칠할 이유가 없다.
        .contentShape(Rectangle())
        // 행 클릭 = **그 세션으로 이동**. 접힌 걸 누르면 터미널이 그 칸으로 옮겨가고,
        // 포커스를 따라 이 그룹이 열린다 — 펼침은 이동의 결과지 별도 조작이 아니다.
        .onTapGesture { if !open { onFocusSession(item.tabId) } }
        .accessibilityRow(label: "\(item.title), 파일 \(item.group.rows.count)개"
                          + (item.group.unreadCount > 0 ? ", 안 본 것 \(item.group.unreadCount)개" : "")
                          + (open ? ", 보는 중" : ", 눌러서 이 세션으로 이동"),
                          selected: open,
                          activate: { onFocusSession(item.tabId) })
    }

    @ViewBuilder
    private func rows(_ item: GroupItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(item.group.rows) { row in
                fileRow(row, base: item.group.baseline, tabId: item.tabId, root: item.root)
            }
            if item.group.rows.isEmpty {
                tail("바꾼 파일 없음 — 읽기만 했습니다")
            }
            if item.group.hiddenCount > 0 {
                tail("그 외 \(item.group.hiddenCount)개")
            }
            // 접은 것과 **애초에 못 받은 것**은 다른 사건이라 따로 말한다.
            if item.group.truncatedCount > 0 {
                tail("오래된 항목 \(item.group.truncatedCount)건은 기록이 잘렸습니다")
            }
            // 읽기·웹 조회는 편집 1건에 수십 건이라 같은 목록에 섞으면 바꾼 것이 파묻힌다.
            // 진입 한 줄만 두고 목록은 탭으로 보낸다. `⧉` = "여기서 펼치지 않고 탭으로 연다".
            // 구분선 바로 아래 붙어 있으면 앞 행의 꼬리처럼 읽힌다 — 선 위아래로 숨을 준다.
            HDivider().padding(.top, Space.sm)
            HStack(spacing: Space.sm) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusSlot)
                Text("이 세션 상세")
                    .font(.muxa(.label)).foregroundStyle(Color.pMuted)
                Spacer(minLength: 0)
                // `⧉`(square.on.square)는 이 저장소에서 **IDE 컨텍스트 공유** 표식이라
                // 용도가 겹치고, 시각적으로도 "복사"로 읽힌다. 여기는 탭으로 들어가는 동선이다.
                Image(systemName: "chevron.right")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity)
            .frame(height: RowHeight.row)
            .padding(.top, Space.tight)
            .contentShape(Rectangle())
            .onTapGesture { onOpenReferences(item.tabId, item.title) }
            .clickCursor()
            .accessibilityRow(label: "이 세션 상세 열기",
                              activate: { onOpenReferences(item.tabId, item.title) })
        }
    }

    @ViewBuilder
    private func fileRow(_ row: AgentChangeRow, base: String?, tabId: TabID,
                         root: String?) -> some View {
        let rel = relative(row.path, root: root)
        HStack(spacing: Space.sm) {
            switch row.mark {
            case .git(let code):
                GitStatusBadge(code: code, weight: row.isUnread ? .semibold : .regular)
            case .committed:
                // git이 조용한데 디스크는 바뀌었다 = 커밋됐다. 무채 — git 축의 색을 빌리지 않는다.
                Image(systemName: "checkmark")
                    .font(.muxa(.micro, weight: row.isUnread ? .semibold : .regular))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusSlot)
                    .accessibilityLabel("커밋됨") // 없으면 VO가 "checkmark"로 읽는다
            }
            // 굵기·색이 **안 봤음** 전용 채널이다(선택은 채움이 말한다).
            GitFileLabel(path: rel,
                         weight: row.isUnread ? .semibold : .regular,
                         tone: row.isUnread ? Color.pFg : Color.pMuted)
            // **오른쪽 가장자리를 세운다.** 없으면 시각이 파일명 뒤에 매달려 행마다 끝이 달라지고,
            // 채움도 글자 길이만큼만 칠해진다 — 옆 `GitChangesSection`은 같은 자리에 이미 이걸 뒀다.
            Spacer(minLength: Space.xs)
            // "커밋됨" 텍스트는 뺀다 — 좌측 무채 ✓가 이미 같은 말을 하면서 시간 열을 밀어냈다.
            GitFileTime(mtime: row.mtime, now: tick)
        }
        .padding(.horizontal, Space.sm)
        .frame(maxWidth: .infinity)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        .modifier(ListRowFill())
        .onTapGesture { open(rel, base: base, tabId: tabId, root: root) }
        .help(rel) // 180pt에서 부모 경로가 사라지므로 전체 경로는 여기로 강등된다
        .accessibilityRow(label: accessibilityLabel(row, rel: rel),
                          activate: { open(rel, base: base, tabId: tabId, root: root) })
    }

    /// VO가 읽을 행 이름 — 굵기·색은 스크린리더에 존재하지 않으므로 **말로** 해야 한다.
    private func accessibilityLabel(_ row: AgentChangeRow, rel: String) -> String {
        var parts = [basename(rel)]
        switch row.mark {
        case .git(let code): parts.append(GitStatusStyle.label(code))
        case .committed: parts.append("커밋됨")
        }
        if row.isUnread { parts.append("안 봄") }
        return parts.joined(separator: ", ")
    }

    private func tail(_ text: String) -> some View {
        Text(text)
            .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight, alignment: .leading)
    }

    /// 이 패널이 모르는 변경 — **완전성을 참칭하지 않게** 하는 유일한 방어다.
    /// 훅은 `Bash`(sed·스크립트·git mv) 경유 변경을 원리상 못 본다. Git 패널과 나란히 있었다면
    /// 리포의 진실이 늘 옆에 보였는데, 패널을 가른 대가로 그 방어가 사라졌다.
    private var residual: some View {
        HStack(spacing: Space.sm) {
            Text("이 패널이 모르는 변경 \(unknownToPanel)건")
                .font(.muxa(.label)).foregroundStyle(Color.pMuted)
            Spacer(minLength: 0)
            Text("Git 패널 →").font(.muxa(.caption, weight: .semibold)).foregroundStyle(Color.pBrand)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        .onTapGesture { onOpenGitPanel() }
        .accessibilityRow(label: "이 패널이 모르는 변경 \(unknownToPanel)건, Git 패널 열기",
                          activate: onOpenGitPanel)
        .padding(.horizontal, Space.xs)
    }

    // MARK: 파생

    /// 화면에 세울 그룹 하나 — 탭 하나에 대응한다.
    struct GroupItem {
        let key: String
        let tabId: TabID
        let title: String
        let group: AgentChangeGroup
        /// 그 탭이 도는 폴더 — 경로 라벨·diff 인자의 기준.
        let root: String?
        /// 이 그룹의 diff 기준 리비전. 없으면 열 때 HEAD로 떨어진다.
        var baseline: String? { group.baseline }
    }

    /// 지금 펼칠 그룹. 포커스된 탭의 세션이 원칙이되, **그 탭이 세션이 아닐 때**
    /// (뷰어 탭·일반 터미널을 보고 있을 때) 맨 위 그룹으로 떨어진다 —
    /// 안 그러면 접힌 행만 남아 패널이 죽은 화면이 된다. 맨 위는 정렬상 가장 안 본 게 많은 세션이다.
    private var openKey: String? {
        let items = groups
        if let cur = store.currentTabId, items.contains(where: { $0.tabId == cur }) {
            return cur.uuid.uuidString
        }
        return items.first?.key
    }

    /// 열린 세션(= 보고 있는 것)을 **맨 위**에 세운다 — 유일하게 내용이 달린 그룹이라
    /// 아래에 있으면 접힌 행들을 지나 스크롤해야 한다.
    private var groups: [GroupItem] {
        store.agentChanges.compactMap { tabId, set -> GroupItem? in
            let g = AgentChangeDisplay.group(from: set, status: status, mtimes: mtimes)
            // 변경이 없어도 **참고가 있으면 세운다** — 읽기만 한 세션(탐색·리뷰)도 한 일이 있고,
            // 그걸 안 세우면 수집해둔 참고 목록에 닿을 방법이 아예 없다.
            guard !g.rows.isEmpty || !set.references.isEmpty else { return nil }
            return GroupItem(key: tabId.uuid.uuidString, tabId: tabId,
                             title: g.title ?? store.tabTitle(tabId), group: g,
                             root: store.effectiveCwds[tabId] ?? dir)
        }
        // 보는 세션이 먼저, 그다음 **안 본 개수가 많은 순**. 예전엔 제목 알파벳순이라
        // 헤더 배지가 "12건 안 봤다"고 광고하는 세션이 이름 탓에 아래로 밀렸다 —
        // 배지가 말하는 긴급도를 정렬이 배신했다.
        .sorted { lhs, rhs in
            let l = lhs.tabId == store.currentTabId, r = rhs.tabId == store.currentTabId
            if l != r { return l }
            if lhs.group.unreadCount != rhs.group.unreadCount {
                return lhs.group.unreadCount > rhs.group.unreadCount
            }
            return lhs.title < rhs.title
        }
    }



    /// 저장소 루트 기준 상대경로 — 행 라벨·diff 인자가 쓴다(git은 상대경로로 말한다).
    /// 그 탭의 cwd(없으면 패널 dir) 기준 상대경로 — 라벨과 diff 인자가 함께 쓴다.
    /// 기준이 틀리면 라벨이 `…sandbox/docs`처럼 머리부터 잘려 읽을 수 없게 된다.
    private func relative(_ absolute: String, root: String?) -> String {
        guard let base = root ?? dir else { return absolute }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return absolute.hasPrefix(prefix) ? String(absolute.dropFirst(prefix.count)) : absolute
    }

    private func open(_ rel: String, base: String?, tabId: TabID, root: String?) {
        // 기준선이 없으면(아직 못 읽었다) HEAD로 떨어진다 — 열리지 않는 행을 만들지 않는다.
        onOpenDiff(.baselineFile(base: base ?? "HEAD", path: rel, session: tabId))
        // "봤음"은 **그 그룹의 탭**에 찍는다 — 포커스 탭에 찍으면 남의 기록을 건드린다.
        guard let base = root ?? dir else { return }
        store.markAgentChangeSeen(tabId: tabId,
                                  path: (base as NSString).appendingPathComponent(rel))
    }

    // MARK: 새로 고치기

    /// git status·mtime을 읽어 **절대경로 키**로 맞춘다. 수집 경로는 절대, git은 상대라
    /// 여기서 맞추지 않으면 상태가 통째로 nil이 되어 모든 행이 "커밋됨"으로 뜬다(실측 버그).
    ///
    /// 기준을 패널의 `dir`이 아니라 **탭별 cwd**로 잡는다. 프로젝트 폴더가 저장소 루트가
    /// 아닐 수 있고(워크스페이스만 열어둔 경우), 탭마다 다른 저장소에서 돌 수도 있다.
    private func refresh() async {
        let paths = Set(store.agentChanges.values.flatMap { $0.entries.keys })

        // 수집이 있는 탭들의 cwd를 모아 중복을 없앤다 — 저장소마다 status 한 번씩.
        var roots = Set(store.agentChanges.keys.compactMap { store.effectiveCwds[$0] })
        if let dir { roots.insert(dir) }
        guard !roots.isEmpty else { status = [:]; mtimes = [:]; unknownToPanel = 0; return }

        var map: [String: Character] = [:]
        for root in roots {
            guard let st = await GitService.status(in: root) else { continue }
            for change in st.changes {
                let abs = (root as NSString).appendingPathComponent(change.opPath)
                // 인덱스·워크트리 중 의미 있는 쪽 — 미추적은 `?`.
                map[abs] = change.isUntracked ? "?" : (change.worktree != " " ? change.worktree : change.index)
            }
        }
        status = map

        // stat은 메인을 막지 않게 떼어낸다 — 수백 파일이면 30초마다 그만큼의 syscall이다.
        let targets = paths
        mtimes = await Task.detached(priority: .utility) {
            var times: [String: Date] = [:]
            for path in targets {
                times[path] = (try? FileManager.default
                    .attributesOfItem(atPath: path)[.modificationDate]) as? Date
            }
            return times
        }.value

        // git이 아는 변경 − 수집된 경로. 에이전트의 Bash 변경뿐 아니라 **사용자 본인의 편집도**
        // 여기 들어온다 — 그래서 라벨이 "귀속 안 된"이 아니라 "이 패널이 모르는"이다.
        unknownToPanel = map.keys.filter { !paths.contains($0) }.count
    }
}
