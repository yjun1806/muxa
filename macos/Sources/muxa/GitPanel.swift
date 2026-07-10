import SwiftUI

/// 활성 프로젝트 폴더의 git 패널(우측). [변경사항] 브랜치·변경파일, [히스토리] 최근 커밋.
/// 파일/커밋 클릭 → onOpenDiff로 diff 시트를 연다. 읽기 전용(M3). 스테이징·커밋은 M4.
struct GitPanel: View {
    let dir: String?
    /// 세션 기준선(rev-parse HEAD) — "이번 세션" 탭이 base..HEAD 커밋을 구하는 기준. nil이면 기록 전.
    var sessionBase: String?
    /// "여기까지 봤음" — 기준선을 현재 HEAD로 리셋(상위 AppState가 프로젝트 값 타입을 갱신).
    var onResetBaseline: () -> Void = {}
    /// 리뷰 코멘트 제출 — 포맷된 지시 텍스트를 포커스 터미널에 붙인다. 성공(터미널 있음)이면 true → 코멘트 소비.
    var onSendReview: (String) -> Bool = { _ in false }
    var onOpenDiff: (GitDiffTarget) -> Void

    private enum Mode: String, CaseIterable {
        case changes = "변경사항"
        case session = "이번 세션"
        case history = "히스토리"
    }

    @State private var mode: Mode = .changes
    @State private var status: GitStatus?
    @State private var commits: [GitCommit] = []
    @State private var sessionCommits: [GitCommit] = []
    @State private var branches: [String] = []
    @State private var loaded = false
    @State private var watcher: FileWatcher?
    @State private var commitMessage = ""
    @State private var commitError: String?
    @State private var syncBusy = false
    @State private var syncError: String?
    @State private var gh: GitService.GHStatus?
    /// canonical repo 루트(리뷰 코멘트 키) — 진입 시 1회 계산. nil이면 리뷰 바 숨김.
    @State private var reviewRoot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            reviewBar
            if let syncError {
                Text(syncError)
                    .font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.pBorder).frame(height: 1)
            }
            if dir != nil, loaded, status == nil {
                label("git 저장소 아님")
            } else if dir == nil {
                label("프로젝트 경로 없음")
            } else {
                picker
                Rectangle().fill(Color.pBorder).frame(height: 1)
                switch mode {
                case .changes: changesView
                case .session: sessionView
                case .history: historyView
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 폭은 상위(ContentView)가 리사이즈로 지정
        .background(Color.pPanel)
        .task(id: dir) {
            gh = nil // 프로젝트 전환 시 이전 PR 배지 즉시 제거(네트워크 대기 동안 stale 방지)
            reviewRoot = nil
            await refresh()
            await refreshGH() // gh 배지: 진입 시 1회만(과한 폴링 금지)
            if let dir { reviewRoot = await GitService.repoRoot(in: dir) } // 리뷰 코멘트 키
            if let dir { watcher = FileWatcher(path: dir) } // B-2: 변경 시 git 패널 자동 갱신
        }
        .onChange(of: watcher?.changeSeq) { _, _ in Task { await refresh() } }
        .onChange(of: sessionBase) { _, _ in Task { await refresh() } } // 기준선 기록·리셋 후 세션 커밋 재계산
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            branchLabel
            if let status {
                if status.ahead > 0 { counter("arrow.up", status.ahead) }
                if status.behind > 0 { counter("arrow.down", status.behind) }
            }
            if let gh { prBadge(gh) }
            Spacer(minLength: 4)
            if status != nil {
                if syncBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
                } else {
                    iconButton("arrow.down.to.line", help: "Pull") { runSync { await GitService.pull(in: $0) } }
                    iconButton("arrow.up.to.line", help: "Push") { runSync { await GitService.push(in: $0) } }
                }
            }
            iconButton("arrow.clockwise", help: "새로고침") { Task { await refresh(); await refreshGH() } }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    /// 리뷰 코멘트 제출 바 — 미제출 코멘트가 있으면 개수 + "N개 보내기"(포커스 터미널에 붙여넣기).
    /// 스토어(@Observable)를 body에서 읽어 코멘트 add/delete에 반응한다. 없으면 아무것도 안 그린다.
    @ViewBuilder
    private var reviewBar: some View {
        if let root = reviewRoot {
            let pending = ReviewCommentStore.shared.comments(inRepo: root)
            if !pending.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.system(size: 11)).foregroundStyle(Color.pMuted)
                    Text("리뷰 코멘트 \(pending.count)개").font(.system(size: 11)).foregroundStyle(Color.pFg)
                    Spacer(minLength: 0)
                    Button {
                        let text = ReviewCommentFormat.instruction(pending)
                        if onSendReview(text) { _ = ReviewCommentStore.shared.consumeAll(inRepo: root) }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "paperplane").font(.system(size: 10))
                            Text("\(pending.count)개 보내기").font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(nsColor: Palette.gitAdded))
                    .help("코멘트를 포커스 터미널에 붙여 다음 턴 지시로 보냄")
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(Color.pPanel)
                Rectangle().fill(Color.pBorder).frame(height: 1)
            }
        }
    }

    /// 브랜치명 — git 저장소면 로컬 브랜치 목록 메뉴, 아니면 "Git" 라벨.
    @ViewBuilder
    private var branchLabel: some View {
        if let status, !branches.isEmpty, let dir {
            Menu {
                ForEach(branches, id: \.self) { b in
                    Button {
                        runSync { await GitService.checkout(b, in: $0) }
                    } label: {
                        if b == status.branch { Label(b, systemImage: "checkmark") } else { Text(b) }
                    }
                    .disabled(b == status.branch)
                }
            } label: {
                Text(status.branch)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(syncBusy)
        } else {
            Text(status?.branch ?? "Git")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
        }
    }

    /// GitHub PR 배지 — #번호 + 상태색(open 초록·merged 보라·closed 빨강) + CI 롤업 아이콘. 클릭 시 브라우저로 PR 열기.
    private func prBadge(_ gh: GitService.GHStatus) -> some View {
        let stateColor = prStateColor(gh.state)
        return Button {
            if let dir { Task { await GitService.ghOpenPR(in: dir) } }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.pull").font(.system(size: 9))
                Text("#\(gh.prNumber)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                if let rollup = gh.rollup {
                    Image(systemName: checkIcon(rollup)).font(.system(size: 9, weight: .bold))
                        .foregroundStyle(checkColor(rollup))
                }
            }
            .foregroundStyle(stateColor)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(stateColor.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(prHelp(gh))
    }

    /// PR 상태 → 색. open/closed는 git 추가·삭제색 재사용, merged는 전용 보라(Palette).
    private func prStateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "OPEN": return Color(nsColor: Palette.gitAdded)
        case "MERGED": return Color(nsColor: Palette.prMerged)
        case "CLOSED": return Color(nsColor: Palette.gitDeleted)
        default: return Color.pMuted
        }
    }

    /// CI 롤업 → 색(통과 초록·실패 빨강·진행중 노랑, Palette 재사용).
    private func checkColor(_ check: GitService.GHStatus.Check) -> Color {
        switch check {
        case .passing: return Color(nsColor: Palette.gitAdded)
        case .failing: return Color(nsColor: Palette.gitDeleted)
        case .pending: return Color(nsColor: Palette.gitModified)
        }
    }

    /// CI 롤업 → 아이콘.
    private func checkIcon(_ check: GitService.GHStatus.Check) -> String {
        switch check {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .pending: return "circle.dotted"
        }
    }

    /// 배지 툴팁 — PR 번호·상태 + CI 통과/실패/진행 카운트.
    private func prHelp(_ gh: GitService.GHStatus) -> String {
        var s = "PR #\(gh.prNumber) · \(gh.state)"
        if gh.rollup != nil {
            s += " · CI 통과 \(gh.passing)"
            if gh.failing > 0 { s += " 실패 \(gh.failing)" }
            if gh.pending > 0 { s += " 진행 \(gh.pending)" }
        }
        return s
    }

    /// 헤더용 아이콘 버튼.
    private func iconButton(_ icon: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.pMuted)
        .help(help)
    }

    private var picker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: 변경사항

    @ViewBuilder
    private var changesView: some View {
        if let status {
            VStack(alignment: .leading, spacing: 0) {
                GitCommitBox(message: $commitMessage, stagedCount: status.staged.count,
                             error: commitError, onCommit: { Task { await commit() } })
                Rectangle().fill(Color.pBorder).frame(height: 1)
                if status.isClean {
                    label("변경 없음")
                } else {
                    wholeDiffToolbar
                    Rectangle().fill(Color.pBorder).frame(height: 1)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            section("스테이지됨", status.staged, staged: true)
                            section("변경", status.unstaged, staged: false)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } else {
            label("불러오는 중…")
        }
    }

    /// 변경사항 도구줄 — 워크트리 전체를 한 번에 훑는 통합 diff 서브탭을 연다.
    private var wholeDiffToolbar: some View {
        HStack(spacing: 6) {
            wholeDiffButton("전체 변경 diff", base: nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).frame(height: 28)
    }

    /// 통합 diff 열기 버튼 — base=nil이면 미커밋 전체, base 지정이면 세션 기준선 이후 전체.
    private func wholeDiffButton(_ title: String, base: String?) -> some View {
        Button { onOpenDiff(.all(base: base)) } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack").font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(Color.pFg)
        }
        .buttonStyle(.plain)
        .help("변경 파일 전체를 한 화면에서 훑기")
    }

    /// 섹션(스테이지됨/변경) — 헤더 + 일괄 스테이지·언스테이지 버튼 + 파일 행들.
    @ViewBuilder
    private func section(_ title: String, _ changes: [GitFileChange], staged: Bool) -> some View {
        if !changes.isEmpty, let dir {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.pMuted)
                Text("\(changes.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.pMuted.opacity(0.7))
                Spacer(minLength: 0)
                Button {
                    Task {
                        _ = staged ? await GitService.unstageAll(in: dir) : await GitService.stageAll(in: dir)
                        await refresh()
                    }
                } label: {
                    Image(systemName: staged ? "minus" : "plus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pMuted)
                .help(staged ? "전부 언스테이지" : "전부 스테이지")
            }
            .padding(.horizontal, 10).frame(height: 22)
            ForEach(changes) { fileRow($0, staged: staged, dir: dir) }
        }
    }

    /// 파일 행 — [스테이지/언스테이지 버튼][상태문자][파일명 → diff 열기].
    private func fileRow(_ change: GitFileChange, staged: Bool, dir: String) -> some View {
        let badge = staged ? change.index : change.worktree
        return HStack(spacing: 6) {
            Button {
                Task {
                    _ = staged ? await GitService.unstage(change.opPath, in: dir)
                               : await GitService.stage(change.opPath, in: dir)
                    await refresh()
                }
            } label: {
                Image(systemName: staged ? "minus" : "plus").font(.system(size: 10, weight: .bold))
                    .frame(width: 14)
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted)
            .help(staged ? "언스테이지" : "스테이지")

            Button { onOpenDiff(.file(change)) } label: {
                HStack(spacing: 8) {
                    Text(String(badge))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(badgeColor(badge))
                        .frame(width: 12)
                    Text(basename(change.opPath))
                        .font(.system(size: 12)).foregroundStyle(Color.pFg).lineLimit(1)
                    Text(parentDir(change.opPath))
                        .font(.system(size: 10)).foregroundStyle(Color.pMuted.opacity(0.8)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(change.path)

            Button { discard(change, in: dir) } label: {
                Image(systemName: "trash").font(.system(size: 10)).frame(width: 14)
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted)
            .help("변경 버리기")
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contextMenu {
            Button("변경 버리기", role: .destructive) { discard(change, in: dir) }
        }
    }

    /// 변경 버리기 — 확인 다이얼로그 후 discard, 성공 시 상태 재조회(FSEvents와 별개로 즉시 갱신).
    private func discard(_ change: GitFileChange, in dir: String) {
        guard DiscardConfirm.confirm(fileName: basename(change.opPath), untracked: change.isUntracked) else { return }
        Task {
            let err = await GitService.discard(change, in: dir)
            if let err { syncError = err } else { await refresh() }
        }
    }

    // MARK: 히스토리

    @ViewBuilder
    private var historyView: some View {
        if commits.isEmpty {
            label(loaded ? "커밋 없음" : "불러오는 중…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(commits) { commitRow($0) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 이번 세션 (기준선 이후 커밋 = 에이전트가 이번 세션에 커밋한 것)

    @ViewBuilder
    private var sessionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionToolbar
            Rectangle().fill(Color.pBorder).frame(height: 1)
            if sessionBase == nil {
                label("기준선 기록 중…")
            } else if sessionCommits.isEmpty {
                label(loaded ? "이번 세션 새 커밋 없음" : "불러오는 중…")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sessionCommits) { commitRow($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// 세션 도구줄 — 커밋 수 + 세션 전체 diff + "여기까지 봤음"(기준선을 현재 HEAD로 리셋).
    private var sessionToolbar: some View {
        HStack(spacing: 6) {
            Text("이번 세션 커밋").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.pMuted)
            Text("\(sessionCommits.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.pMuted.opacity(0.7))
            Spacer(minLength: 0)
            if let base = sessionBase {
                wholeDiffButton("세션 전체", base: base) // base..worktree = 이번 세션 전체(커밋+미커밋)
            }
            Button(action: onResetBaseline) {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle").font(.system(size: 10))
                    Text("여기까지 봤음").font(.system(size: 10))
                }
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted)
            .help("기준선을 현재 HEAD로 리셋 — 이후 커밋만 '이번 세션'에 표시")
            .disabled(sessionBase == nil)
        }
        .padding(.horizontal, 10).frame(height: 26)
    }

    private func commitRow(_ commit: GitCommit) -> some View {
        Button { onOpenDiff(.commit(hash: commit.hash, subject: commit.subject)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.pMuted)
                    Text(commit.author).font(.system(size: 10)).foregroundStyle(Color.pMuted).lineLimit(1)
                    Text("·").foregroundStyle(Color.pMuted)
                    Text(commit.date).font(.system(size: 10)).foregroundStyle(Color.pMuted).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 공용

    private func counter(_ icon: String, _ n: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 9))
            Text("\(n)").font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(Color.pMuted)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private func badgeColor(_ c: Character) -> Color {
        switch c {
        case "A", "?": return .green
        case "M": return .orange
        case "D": return .red
        case "R", "C": return .blue
        default: return Color.pMuted
        }
    }

    private func parentDir(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    /// 스테이지된 변경을 커밋 → 성공 시 메시지 비우고 갱신, 실패 시 에러 표시.
    private func commit() async {
        guard let dir else { return }
        commitError = await GitService.commit(message: commitMessage, in: dir)
        if commitError == nil {
            commitMessage = ""
            await refresh()
        }
    }

    /// pull/push/checkout 공통 실행 — 진행 표시·에러 표시·성공 후 갱신.
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
                await refreshGH() // 브랜치 전환·pull/push 후 PR 배지도 갱신(이전 브랜치 PR stale 방지)
            }
        }
    }

    private func refresh() async {
        guard let dir else {
            status = nil
            commits = []
            sessionCommits = []
            branches = []
            loaded = true
            return
        }
        status = await GitService.status(in: dir)
        commits = status == nil ? [] : await GitService.log(in: dir)
        branches = status == nil ? [] : await GitService.localBranches(in: dir)
        // 이번 세션 = 기준선 이후 커밋(base..HEAD). 기준선 없거나 git 저장소 아니면 빈 목록.
        if let base = sessionBase, status != nil {
            sessionCommits = await GitService.sessionCommits(base: base, in: dir)
        } else {
            sessionCommits = []
        }
        loaded = true
    }

    /// gh 배지 갱신 — git 저장소일 때만 시도. gh 미설치·PR 없음이면 nil(배지 숨김). FSEvents엔 안 물림(과한 폴링 금지).
    private func refreshGH() async {
        guard let dir, status != nil else { gh = nil; return }
        gh = await GitService.ghStatus(in: dir)
    }
}
