import SwiftUI

/// diff를 열 대상 — 변경 파일 또는 커밋. .sheet(item:)용 Identifiable.
enum GitDiffTarget: Identifiable {
    case file(GitFileChange)
    case commit(hash: String, subject: String)

    var id: String {
        switch self {
        case .file(let change): return "f:\(change.path)"
        case .commit(let hash, _): return "c:\(hash)"
        }
    }

    var title: String {
        switch self {
        case .file(let change): return change.path
        case .commit(_, let subject): return subject
        }
    }

    /// 탭 라벨(짧게).
    var tabTitle: String {
        switch self {
        case .file(let change): return basename(change.path)
        case .commit(let hash, _): return String(hash.prefix(7))
        }
    }

    var tabIcon: String {
        switch self {
        case .file: return "plusminus"
        case .commit: return "clock"
        }
    }
}

/// unified diff 뷰어(시트). +초록/-빨강/@@ 청록으로 라인 색을 준다. 읽기 전용.
/// 큰 diff 대비 LazyVStack + 가로·세로 스크롤. 폰트·색 고도화는 B(뷰어)에서.
struct DiffView: View {
    let target: GitDiffTarget
    let dir: String
    var chrome: Bool = true // 그룹 서브탭 안에서는 자체 헤더 숨김
    var onClose: () -> Void

    @State private var lines: [String] = []
    @State private var loaded = false
    @State private var applying = false
    @State private var stageError: String?
    @State private var watcher: FileWatcher? // 파일 diff만 디스크 변경 감시(커밋 diff는 불변이라 nil)
    @State private var lastMTime: Date?      // 이 파일 실제 변경만 재로드(FSEvents 재귀 소음·스테이지 무시)
    /// 현재 파일의 최신 변경 상태 — 스테이지/언스테이지로 index·worktree가 바뀌므로 target의
    /// 캡처값(stale)이 아니라 매 로드마다 git status에서 다시 읽어 라우팅·버튼 판단에 쓴다.
    @State private var change: GitFileChange?

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                header
                Rectangle().fill(Color.pBorder).frame(height: 1)
            }
            stageToolbar
            if !loaded {
                centerLabel("불러오는 중…")
            } else if lines.isEmpty {
                centerLabel("변경 내용 없음")
            } else {
                CodeWebView(
                    html: CodeHTML.diff(lines: lines, dark: GhosttyRuntime.systemIsDark, stageable: hunkStageable),
                    onMessage: hunkStageable ? { idx in Task { @MainActor in await stageHunk(idx) } } : nil,
                    busy: applying
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) {
            await load()
            watcher = fileWatcher() // 파일 diff면 부모 디렉토리 감시 시작(커밋 diff는 nil)
        }
        .onChange(of: watcher?.changeSeq) { _, _ in Task { await reloadIfChanged() } }
    }

    /// 절대 경로(repo dir + 상대경로). status의 opPath는 repo 루트 기준 상대경로다.
    private func absolutePath(_ rel: String) -> String {
        (dir as NSString).appendingPathComponent(rel)
    }

    /// 파일 diff일 때만 부모 디렉토리에 FileWatcher를 건다(커밋 diff는 불변이라 감시 불필요).
    private func fileWatcher() -> FileWatcher? {
        guard case .file(let initial) = target else { return nil }
        let abs = absolutePath(initial.opPath)
        return FileWatcher(path: (abs as NSString).deletingLastPathComponent)
    }

    /// FSEvents는 부모 디렉토리 전체(재귀)를 알린다 → 이 파일 mtime이 실제 바뀐 경우만 재로드.
    /// 스테이지 재적용 중(applying)이면 건너뛴다 — runStage 끝의 load()가 최신을 반영한다.
    private func reloadIfChanged() async {
        guard !applying, case .file(let initial) = target else { return }
        let abs = absolutePath(initial.opPath)
        let m = (try? FileManager.default.attributesOfItem(atPath: abs)[.modificationDate]) as? Date
        guard m != lastMTime else { return }
        await load()
    }

    /// diff 대상이 변경 파일일 때만 값이 있다(.commit은 읽기 전용). load()가 최신 status로 채운다.
    private var fileChange: GitFileChange? {
        if case .file = target { return change }
        return nil
    }

    /// hunk 단위 스테이지 가능 여부 — 추적되는 파일의 언스테이지 변경만(untracked·삭제 diff는 제외).
    private var hunkStageable: Bool {
        guard let change = fileChange, !change.isUntracked, change.worktree == "M" else { return false }
        return true
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plusminus").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            Text(target.title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            Button("닫기", action: onClose)
                .keyboardShortcut(.cancelAction) // Esc
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.pPanel)
    }

    private func centerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 변경 파일 diff 위의 스테이지 도구줄 — [전체 스테이지/언스테이지] 버튼(hunk 버튼은 HTML 안).
    @ViewBuilder
    private var stageToolbar: some View {
        if let change = fileChange {
            HStack(spacing: 8) {
                if change.worktree != " " {
                    toolbarButton("전체 스테이지", icon: "plus") { Task { await stageWholeFile(change) } }
                }
                if change.isStaged {
                    toolbarButton("언스테이지", icon: "minus") { Task { await unstageWholeFile(change) } }
                }
                toolbarButton("변경 버리기", icon: "trash", destructive: true) { discardFile(change) }
                if let stageError {
                    Text(stageError)
                        .font(.system(size: 10)).foregroundStyle(.red).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if applying { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16) }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.pPanel)
            Rectangle().fill(Color.pBorder).frame(height: 1)
        }
    }

    private func toolbarButton(_ title: String, icon: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.pBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color(nsColor: Palette.gitDeleted) : Color.pFg)
        .disabled(applying)
    }

    // MARK: 스테이지 액션 — 성공 시 diff를 다시 읽는다(git 패널은 FSEvents로 자동 갱신).

    private func stageWholeFile(_ change: GitFileChange) async {
        await runStage { await GitService.stage(change.opPath, in: dir) ? nil : "스테이지 실패" }
    }

    private func unstageWholeFile(_ change: GitFileChange) async {
        await runStage { await GitService.unstage(change.opPath, in: dir) ? nil : "언스테이지 실패" }
    }

    /// 변경 버리기 — 확인 다이얼로그 후 discard, 성공 시 diff 재로딩(git 패널은 FSEvents로 갱신).
    private func discardFile(_ change: GitFileChange) {
        guard DiscardConfirm.confirm(fileName: basename(change.opPath), untracked: change.isUntracked) else { return }
        Task { await runStage { await GitService.discard(change, in: dir) } }
    }

    private func stageHunk(_ index: Int) async {
        guard fileChange != nil else { return }
        guard let patch = DiffPatch.patch(forHunk: index, in: DiffPatch.parse(lines)) else {
            stageError = "이 hunk는 스테이지할 수 없어요"
            return
        }
        await runStage { await GitService.applyCached(patch: patch, in: dir) }
    }

    /// 스테이지 계열 공통 실행 — 진행 표시·에러 표시·성공 시 diff 재로딩.
    private func runStage(_ op: @escaping () async -> String?) async {
        guard !applying else { return }
        applying = true
        stageError = nil
        let err = await op()
        if let err { stageError = err } else { await load() } // 재로딩 끝까지 가드 유지(중복 클릭 drop)
        applying = false
    }

    private func load() async {
        loaded = false
        stageError = nil
        let text: String
        switch target {
        case .file(let initial):
            // 스테이지 상태가 바뀌었을 수 있으니 최신 status에서 이 경로의 change를 다시 찾아 라우팅한다.
            // (stale target으로 --cached/언스테이지 브랜치를 잘못 타 '변경 내용 없음'이 뜨던 문제 방지)
            let path = initial.opPath
            let fresh = (await GitService.status(in: dir))?.changes.first { $0.opPath == path }
            let cur = fresh ?? initial
            change = cur
            // 워처 재로드 판별용 기준 mtime 갱신(스테이지는 worktree 파일 mtime을 바꾸지 않아 중복 재로드 없음).
            lastMTime = (try? FileManager.default.attributesOfItem(atPath: absolutePath(cur.opPath))[.modificationDate]) as? Date
            text = await GitService.fileDiff(cur, in: dir)
        case .commit(let hash, _):
            change = nil
            text = await GitService.commitDiff(hash, in: dir)
        }
        lines = text.components(separatedBy: "\n")
        loaded = true
    }
}
