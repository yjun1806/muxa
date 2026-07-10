import SwiftUI

/// 활성 프로젝트 폴더의 git 패널(우측). [변경사항] 브랜치·변경파일, [히스토리] 최근 커밋.
/// 파일/커밋 클릭 → onOpenDiff로 diff 시트를 연다. 읽기 전용(M3). 스테이징·커밋은 M4.
struct GitPanel: View {
    let dir: String?
    var onOpenDiff: (GitDiffTarget) -> Void

    private enum Mode: String, CaseIterable {
        case changes = "변경사항"
        case history = "히스토리"
    }

    @State private var mode: Mode = .changes
    @State private var status: GitStatus?
    @State private var commits: [GitCommit] = []
    @State private var branches: [String] = []
    @State private var loaded = false
    @State private var watcher: FileWatcher?
    @State private var commitMessage = ""
    @State private var commitError: String?
    @State private var syncBusy = false
    @State private var syncError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
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
                case .history: historyView
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        .task(id: dir) {
            await refresh()
            if let dir { watcher = FileWatcher(path: dir) } // B-2: 변경 시 git 패널 자동 갱신
        }
        .onChange(of: watcher?.changeSeq) { _, _ in Task { await refresh() } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            branchLabel
            if let status {
                if status.ahead > 0 { counter("arrow.up", status.ahead) }
                if status.behind > 0 { counter("arrow.down", status.behind) }
            }
            Spacer(minLength: 4)
            if status != nil {
                if syncBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
                } else {
                    iconButton("arrow.down.to.line", help: "Pull") { runSync { await GitService.pull(in: $0) } }
                    iconButton("arrow.up.to.line", help: "Push") { runSync { await GitService.push(in: $0) } }
                }
            }
            iconButton("arrow.clockwise", help: "새로고침") { Task { await refresh() } }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
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
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
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
            if msg == nil { await refresh() }
        }
    }

    private func refresh() async {
        guard let dir else {
            status = nil
            commits = []
            branches = []
            loaded = true
            return
        }
        status = await GitService.status(in: dir)
        commits = status == nil ? [] : await GitService.log(in: dir)
        branches = status == nil ? [] : await GitService.localBranches(in: dir)
        loaded = true
    }
}
