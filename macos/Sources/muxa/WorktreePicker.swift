import SwiftUI

/// 워크트리 선택/생성 시트 — 기존 워크트리 목록 + 새 워크트리 생성 폼.
/// 선택/생성 결과(브랜치명, 절대경로)를 onPick으로 넘겨 프로젝트로 추가한다.
struct WorktreePicker: View {
    let dir: String
    var onPick: (String, String) -> Void
    /// 제거된 워크트리의 절대경로 — 그 폴더를 쓰던 프로젝트를 호출부가 닫는다(고아·좀비 서비스 방지).
    var onRemoved: (String) -> Void
    var onCancel: () -> Void

    @State private var worktrees: [GitWorktree] = []
    @State private var branches: [String] = []
    @State private var defaultBranch: String?
    @State private var loaded = false
    @State private var newBranchName = ""
    @State private var baseRef = "HEAD"
    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HDivider()
            content
            if let errorMessage {
                Text(errorMessage)
                    .font(.muxa(.label)).foregroundStyle(Color.pDanger)
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
            MuxaIcon(name: MuxaSymbol.gitBranch).foregroundStyle(Color.pMuted)
            Text("워크트리").font(.muxa(.title, weight: .semibold)).foregroundStyle(Color.pFg)
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
                        // 첫 항목은 메인 워크트리(제거 불가). 나머지에만 휴지통 노출.
                        ForEach(Array(worktrees.enumerated()), id: \.element.id) { i, wt in
                            existingRow(wt, isMain: i == 0)
                        }
                    }
                    sectionLabel("새 워크트리")
                    newForm
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func existingRow(_ wt: GitWorktree, isMain: Bool) -> some View {
        HStack(spacing: 8) {
            Button { onPick(wt.displayName, wt.path) } label: {
                HStack(spacing: 8) {
                    MuxaIcon(name: MuxaSymbol.gitBranch, size: TypeScale.label).foregroundStyle(Color.pMuted)
                    Text(wt.displayName).font(.muxa(.body)).foregroundStyle(Color.pFg).lineLimit(1)
                    if isMain {
                        Text("메인").font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.pBorder).clipShape(Capsule())
                    }
                    Spacer(minLength: 8)
                    Text(displayPath(wt.path, home: SystemPaths.home))
                        .font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(1).truncationMode(.head)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help(wt.path)
            // 메인이 아니고 브랜치가 있으며 기본 브랜치와 다르면 "병합 후 정리" 노출(마무리 원액션).
            if !isMain, let branch = wt.branch, let target = defaultBranch, branch != target {
                Button { mergeCleanup(wt, branch: branch, target: target) } label: {
                    MuxaIcon(name: MuxaSymbol.gitBranch, size: TypeScale.label).foregroundStyle(Color.pMuted)
                }
                .buttonStyle(.plain).disabled(busy)
                .help("\(target)에 병합 후 정리")
            }
            // 메인 워크트리는 제거 불가. 비강제 remove라 변경사항이 있으면 git이 거부한다.
            if !isMain {
                Button { remove(wt) } label: {
                    Image(systemName: "trash").font(.muxa(.label)).foregroundStyle(Color.pMuted)
                }
                .buttonStyle(.plain).disabled(busy)
                .help("워크트리 제거")
            }
        }
        .padding(.horizontal, 16).frame(height: 30)
    }

    /// 워크트리 제거(비강제) → 그 폴더를 쓰던 프로젝트 정리 → 목록 갱신. dirty면 git이 거부하고 사유를 보인다.
    private func remove(_ wt: GitWorktree) {
        busy = true
        errorMessage = nil
        Task {
            if let msg = await GitService.worktreeRemove(wt.path, in: dir) {
                errorMessage = msg
            } else {
                onRemoved(wt.path) // 폴더가 사라졌다 — 그걸 쓰던 프로젝트·서비스도 닫는다
                await load()
            }
            busy = false
        }
    }

    private var newForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("브랜치명 (예: feature/x)", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("base").font(.muxa(.label)).foregroundStyle(Color.pMuted)
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
            .font(.muxa(.caption, weight: .semibold)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func center(_ t: String) -> some View {
        Text(t)
            .font(.muxa(.body)).foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 병합 후 정리(마무리 원액션) — 확인 → ff 병합 → 워크트리 제거 → 브랜치 삭제 → 목록 갱신.
    /// 어느 단계든 실패하면 사유를 알럿으로 표면화한다(충돌은 "터미널에서 해결" 안내).
    private func mergeCleanup(_ wt: GitWorktree, branch: String, target: String) {
        guard WorktreeMergeConfirm.confirm(branch: branch, target: target) else { return }
        busy = true
        errorMessage = nil
        Task {
            let err = await GitService.mergeAndCleanup(
                branch: branch, into: target, worktreePath: wt.path, in: dir)
            if let err {
                WorktreeMergeConfirm.showError(err)
            } else {
                onRemoved(wt.path) // 병합 후 정리도 워크트리 폴더를 지운다 — 같은 정리가 필요하다
                await load()
            }
            busy = false
        }
    }

    private func load() async {
        worktrees = await GitService.worktreeList(in: dir)
        branches = await GitService.localBranches(in: dir)
        defaultBranch = await GitService.defaultBranch(in: dir)
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
