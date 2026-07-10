import SwiftUI

/// 워크트리 선택/생성 시트 — 기존 워크트리 목록 + 새 워크트리 생성 폼.
/// 선택/생성 결과(브랜치명, 절대경로)를 onPick으로 넘겨 프로젝트로 추가한다.
struct WorktreePicker: View {
    let dir: String
    var onPick: (String, String) -> Void
    var onCancel: () -> Void

    @State private var worktrees: [GitWorktree] = []
    @State private var branches: [String] = []
    @State private var loaded = false
    @State private var newBranchName = ""
    @State private var baseRef = "HEAD"
    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            content
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 440, height: 480)
        .background(Color.pPanel)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.pMuted)
            Text("워크트리").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.pFg)
            Spacer()
            Button("닫기", action: onCancel).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            center("불러오는 중…")
        } else if worktrees.isEmpty && branches.isEmpty {
            center("git 저장소가 아닙니다")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !worktrees.isEmpty {
                        sectionLabel("기존 워크트리")
                        ForEach(worktrees) { existingRow($0) }
                    }
                    sectionLabel("새 워크트리")
                    newForm
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func existingRow(_ wt: GitWorktree) -> some View {
        Button { onPick(wt.displayName, wt.path) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(Color.pMuted)
                Text(wt.displayName).font(.system(size: 12)).foregroundStyle(Color.pFg).lineLimit(1)
                Spacer(minLength: 8)
                Text(displayPath(wt.path, home: SystemPaths.home))
                    .font(.system(size: 10)).foregroundStyle(Color.pMuted).lineLimit(1).truncationMode(.head)
            }
            .padding(.horizontal, 16).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(wt.path)
    }

    private var newForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("브랜치명 (예: feature/x)", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("base").font(.system(size: 11)).foregroundStyle(Color.pMuted)
                Picker("", selection: $baseRef) {
                    Text("HEAD").tag("HEAD")
                    ForEach(branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 200)
                Spacer()
                Button(busy ? "생성 중…" : "생성") { create() }
                    .disabled(busy || newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func center(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12)).foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        worktrees = await GitService.worktreeList(in: dir)
        branches = await GitService.localBranches(in: dir)
        loaded = true
    }

    private func create() {
        let name = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busy = true
        errorMessage = nil
        Task {
            let existing = branches.contains(name)
            let result = await GitService.worktreeAdd(branch: name, base: baseRef, newBranch: !existing, in: dir)
            busy = false
            switch result {
            case .ok(let path): onPick(name, path)
            case .failed(let msg): errorMessage = msg
            }
        }
    }
}
