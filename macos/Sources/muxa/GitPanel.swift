import SwiftUI

/// 활성 프로젝트의 git 패널(우측 도구 패널). **에이전트 산출물 리뷰 창구**다 — git 클라이언트가 아니다.
///
/// **두 탭이다: [리뷰 | 히스토리].**
/// 예전엔 [변경사항 | 이번 세션 | 히스토리] 셋이었는데 축이 안 맞았다 — 변경사항은 *상태*(미커밋),
/// 나머지 둘은 *이력*이고 `이번 세션 ⊂ 히스토리`가 완전 포함관계라 같은 커밋이 두 탭에 **중복 렌더**됐다.
/// 배타적으로 생긴 컨트롤(세그먼티드)에 포함관계를 넣으면 어느 쪽도 신뢰가 안 간다.
/// 이제 **리뷰**(지금 만들고 있는 것 = 미커밋 + 기준선 이후 커밋)와 **히스토리**(저장소가 걸어온 길)로
/// 갈랐다. 덤으로 "세션 전체 diff" 버튼의 범위(커밋+미커밋)와 목록의 범위가 비로소 일치한다.
///
/// **"세션"이라는 낱말을 안 쓴다** — tmux 백그라운드 세션과 Claude Code 세션이 이미 선점했다(3중 충돌).
/// UI 문구는 "이번 작업"이고, 코드 필드명(`sessionBase`)은 스냅샷 하위호환 때문에 그대로 둔다.
///
/// 상태는 전부 여기가 소유하고 하위 뷰는 값+클로저만 받는다(controlled).
struct GitPanel: View {
    let dir: String?
    /// 기준선(rev-parse HEAD) — "이번 작업" 커밋(base..HEAD)의 기준. nil이면 기록 전.
    var sessionBase: String?
    /// "여기까지 봤음" — 기준선을 현재 HEAD로 리셋.
    var onResetBaseline: () -> Void = {}
    /// 리뷰 코멘트 제출 — 포맷된 지시를 포커스 터미널에 붙인다. 성공이면 true → 코멘트 소비.
    var onSendReview: (String) -> Bool = { _ in false }
    /// 변경 파일을 **일반 뷰어**로 열기(md 렌더링·코드 하이라이트) — 절대 경로.
    /// diff가 "무엇이 바뀌었나"를 말한다면 뷰어는 "지금 이 문서가 어떤 모습인가"를 말한다.
    /// 에이전트가 쓴 README·설계 문서를 diff 조각이 아니라 완성된 형태로 읽고 싶을 때 쓴다.
    var onOpenInViewer: ((String) -> Void)?
    var onOpenDiff: (GitDiffTarget) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case review = "리뷰"
        case history = "히스토리"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .review: return "checklist"
            case .history: return "clock"
            }
        }
    }

    @State private var mode: Mode = .review
    @State private var status: GitStatus?
    @State private var commits: [GitCommit] = []
    @State private var sessionCommits: [GitCommit] = []
    @State private var branches: [String] = []
    @State private var loaded = false
    @State private var watcher: FileWatcher?
    @State private var syncBusy = false
    @State private var syncError: String?
    @State private var gh: GitService.GHStatus?
    /// canonical repo 루트(리뷰 코멘트·리뷰 상태 키) — 진입 시 1회. nil이면 리뷰 바 숨김.
    @State private var reviewRoot: String?
    @State private var pathState: PathState = .ok
    /// 진행 중인 갱신 — FSEvents가 연달아 오면 이전 것을 취소해 결과가 뒤바뀌어 착지하지 않게 한다.
    @State private var refreshTask: Task<Void, Never>?

    /// 펼친 커밋 해시. **동시에 하나만** — 폭이 180pt까지 좁아질 수 있어 여럿이 펼쳐지면
    /// 커밋 행과 파일 행의 구분이 무너진다(아코디언).
    @State private var expandedCommit: String?
    /// 커밋 해시 → 파일 목록 캐시. **커밋은 불변이라 무효화가 필요 없다**(한 번 조회로 끝).
    @State private var commitFiles: [String: [GitCommitFile]] = [:]
    /// 상대 시각 표시가 굳지 않게 하는 틱 — 30초마다 갱신(분 단위 표시라 이 이상 자주 볼 이유가 없다).
    @State private var now = Date()
    /// 변경 파일별 마지막 수정 시각 — 행 꼬리표("3m"). status 갱신 때 함께 읽는다.
    /// **셸아웃이 아니라 `FileManager` 속성 조회**라 파일이 많아도 싸다.
    @State private var mtimes: [String: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitPanelHeader(status: status, branches: branches, gh: gh, syncBusy: syncBusy, dir: dir,
                           onCheckout: { b in runSync { await GitService.checkout(b, in: $0) } },
                           onPull: { runSync { await GitService.pull(in: $0) } },
                           onPush: { runSync { await GitService.push(in: $0) } },
                           onRefresh: { Task { await refresh(); await refreshGH() } })
            HDivider() // 헤더 높이(panelHeader)가 이 선까지 계산돼 옆 칸 탭바와 아래 경계가 맞는다
            reviewBar
            errorBar
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 폭은 상위(ContentView)가 리사이즈로 지정
        .background(Color.pPanel)
        .task(id: dir) {
            gh = nil // 프로젝트 전환 시 이전 PR 배지 즉시 제거(네트워크 대기 동안 stale 방지)
            reviewRoot = nil
            expandedCommit = nil
            commitFiles = [:]
            await refresh()
            await refreshGH() // gh 배지: 진입 시 1회만(과한 폴링 금지)
            if let dir { reviewRoot = await GitService.repoRoot(in: dir) }
            if let dir { watcher = FileWatcher(path: dir) }
        }
        .tick(every: 30, into: $now)
        .onChange(of: watcher?.changeSeq) { _, _ in scheduleRefresh() }
        .onChange(of: sessionBase) { _, _ in scheduleRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        if dir == nil {
            PanelLabel("프로젝트 경로 없음")
        } else if let reason = pathState.message {
            PanelLabel(reason) // 경로 소실·권한 거부를 "git 저장소 아님"으로 위장하지 않는다
        } else if loaded, status == nil {
            PanelLabel("git 저장소 아님")
        } else {
            PanelTabSwitcher(tabs: Mode.allCases, selection: $mode) { ($0.rawValue, $0.icon) }
            HDivider()
            switch mode {
            case .review:
                GitReviewTab(
                    status: status, dir: dir, loaded: loaded,
                    sessionBase: sessionBase, sessionCommits: sessionCommits,
                    mtimes: mtimes, now: now,
                    commitList: commitList(sessionCommits, showBaseline: false),
                    onResetBaseline: onResetBaseline,
                    onOpenDiff: onOpenDiff,
                    onOpenInViewer: onOpenInViewer)
            case .history:
                GitHistoryTab(commits: commits, loaded: loaded,
                              commitList: commitList(commits, showBaseline: true))
            }
        }
    }

    /// 두 탭이 쓰는 커밋 목록 뷰를 조립한다 — 상태 접근이 여기 모여 있어야 controlled가 유지된다.
    private func commitList(_ list: [GitCommit], showBaseline: Bool) -> GitCommitList {
        GitCommitList(
            commits: list,
            expanded: expandedCommit,
            files: commitFiles,
            baseline: showBaseline ? sessionBase : nil,
            onToggle: toggle,
            onOpenDiff: onOpenDiff,
            onOpenInViewer: onOpenInViewer == nil ? nil : viewerAction(for:))
    }

    /// 커밋 파일 → 뷰어 열기 동작. **지금 워크트리에 그 파일이 있을 때만** 값을 준다.
    ///
    /// 커밋 당시 내용이 아니라 **현재 파일**을 연다 — `FileViewTarget`은 경로로 디스크를 읽는 타입이라
    /// 과거 스냅샷을 그리려면 "내용을 받는 뷰어"로 넓혀야 한다(별도 작업). 그래서 그 뒤 지워졌거나
    /// 이름이 바뀐 파일엔 아이콘을 안 그린다 — 빈 화면을 여는 버튼을 만들지 않는다.
    private func viewerAction(for file: GitCommitFile) -> (() -> Void)? {
        guard let dir, let onOpenInViewer else { return nil }
        let abs = (dir as NSString).appendingPathComponent(file.path)
        guard FileManager.default.fileExists(atPath: abs) else { return nil }
        return { onOpenInViewer(abs) }
    }

    // MARK: 리뷰 코멘트 바

    /// 미제출 코멘트가 있으면 개수 + "N개 보내기"(포커스 터미널에 주입). 없으면 아무것도 안 그린다.
    @ViewBuilder
    private var reviewBar: some View {
        if let root = reviewRoot {
            let pending = ReviewCommentStore.shared.comments(inRepo: root)
            if !pending.isEmpty {
                HStack(spacing: Space.sm) {
                    Image(systemName: "text.bubble").font(.muxa(.label)).foregroundStyle(Color.pMuted)
                    Text("리뷰 코멘트 \(pending.count)개").font(.muxa(.label)).foregroundStyle(Color.pFg)
                    Spacer(minLength: 0)
                    Button {
                        let text = ReviewCommentFormat.instruction(pending)
                        if onSendReview(text) { _ = ReviewCommentStore.shared.consumeAll(inRepo: root) }
                    } label: {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "paperplane").font(.muxa(.caption))
                            Text("\(pending.count)개 보내기").font(.muxa(.label, weight: .medium))
                        }
                    }
                    // 액션이지 git 추가가 아니다 — 기능색(gitAdded)을 UI 액션에 전용하지 않는다.
                    .buttonStyle(.plain).foregroundStyle(Color.pBrand)
                    .help("코멘트를 포커스 터미널에 붙여 다음 턴 지시로 보냄")
                }
                .panelBar(height: RowHeight.bar)
                .background(Color.pPanel)
                HDivider()
            }
        }
    }

    /// 동기화·버리기 실패 — 색만으로 말하지 않게 글리프를 함께 붙인다.
    @ViewBuilder
    private var errorBar: some View {
        if let syncError {
            HStack(spacing: Space.xs) {
                Image(systemName: "exclamationmark.triangle.fill").font(.muxa(.micro))
                Text(syncError).font(.muxa(.caption)).lineLimit(2)
            }
            .foregroundStyle(Color.pDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBar(height: RowHeight.bar)
            HDivider()
        }
    }


    // MARK: 동작

    /// 커밋 펼침 — 아코디언(하나만). 파일 목록은 처음 펼칠 때만 조회하고 이후 캐시를 쓴다.
    private func toggle(_ commit: GitCommit) {
        guard let dir else { return }
        if expandedCommit == commit.hash {
            expandedCommit = nil
            return
        }
        expandedCommit = commit.hash
        guard commitFiles[commit.hash] == nil else { return } // 커밋은 불변 — 재조회 없음
        Task {
            let files = await GitService.commitFiles(commit.hash, in: dir)
            commitFiles[commit.hash] = files
        }
    }


    /// pull/push/checkout 공통 — 진행 표시·에러 표시·성공 후 갱신.
    private func runSync(_ op: @escaping (String) async -> String?) {
        guard let dir, !syncBusy else { return }
        syncBusy = true
        syncError = nil
        Task {
            let msg = await op(dir)
            syncError = msg
            syncBusy = false
            if msg == nil {
                await refresh()
                await refreshGH() // 브랜치 전환·pull/push 후 PR 배지도 갱신(stale 방지)
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }

    private func refresh() async {
        guard let dir else {
            clearGit()
            return
        }
        pathState = PathState.check(dir)
        guard pathState == .ok else {
            clearGit()
            return
        }
        // 네 조회를 **병렬로** — 순차 await면 FSEvents 배치마다 셸아웃이 줄줄이 기다린다.
        async let statusResult = GitService.status(in: dir)
        async let logResult = GitService.log(in: dir)
        async let branchResult = GitService.localBranches(in: dir)
        async let sessionResult = loadSessionCommits(in: dir)
        let (s, allCommits, branchList, session) = await (statusResult, logResult, branchResult, sessionResult)
        guard !Task.isCancelled else { return } // 뒤늦은 결과가 최신 상태를 덮지 않게
        status = s
        commits = s == nil ? [] : allCommits
        branches = s == nil ? [] : branchList
        sessionCommits = s == nil ? [] : session
        loaded = true
        refreshMTimes(s)
    }

    /// 변경 파일들의 마지막 수정 시각 — 행 꼬리표 입력. 디스크 속성만 읽어 셸아웃이 없다.
    private func refreshMTimes(_ status: GitStatus?) {
        guard let dir, let status else {
            mtimes = [:]
            return
        }
        var next: [String: Date] = [:]
        for change in status.changes {
            let abs = (dir as NSString).appendingPathComponent(change.opPath)
            if let d = (try? FileManager.default.attributesOfItem(atPath: abs)[.modificationDate]) as? Date {
                next[change.opPath] = d
            }
        }
        mtimes = next
    }

    private func loadSessionCommits(in dir: String) async -> [GitCommit] {
        guard let base = sessionBase else { return [] }
        return await GitService.sessionCommits(base: base, in: dir)
    }

    private func clearGit() {
        status = nil
        commits = []
        sessionCommits = []
        branches = []
        mtimes = [:]
        loaded = true
    }

    /// gh 배지 갱신 — git 저장소일 때만. FSEvents엔 안 물림(과한 폴링 금지).
    private func refreshGH() async {
        guard let dir, status != nil else { gh = nil; return }
        gh = await GitService.ghStatus(in: dir)
    }
}
