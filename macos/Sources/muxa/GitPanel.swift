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
    @State private var loaded = false
    @State private var watcher: FileWatcher?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
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
            Text(status?.branch ?? "Git")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
            if let status {
                if status.ahead > 0 { counter("arrow.up", status.ahead) }
                if status.behind > 0 { counter("arrow.down", status.behind) }
            }
            Spacer(minLength: 4)
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pMuted)
            .help("새로고침")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
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
            if status.isClean {
                label("변경 없음")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(status.changes) { fileRow($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            label("불러오는 중…")
        }
    }

    private func fileRow(_ change: GitFileChange) -> some View {
        Button { onOpenDiff(.file(change)) } label: {
            HStack(spacing: 8) {
                Text(String(change.badge))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor(change.badge))
                    .frame(width: 12)
                Text(basename(change.path))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                Text(parentDir(change.path))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.pMuted.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(change.path)
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

    private func refresh() async {
        guard let dir else {
            status = nil
            commits = []
            loaded = true
            return
        }
        status = await GitService.status(in: dir)
        commits = status == nil ? [] : await GitService.log(in: dir)
        loaded = true
    }
}
