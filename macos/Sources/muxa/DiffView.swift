import SwiftUI

/// diff를 열 대상 — 변경 파일·커밋·워크트리 전체. .sheet(item:)용 Identifiable.
enum GitDiffTarget: Identifiable {
    case file(GitFileChange)
    case commit(hash: String, subject: String)
    /// 워크트리 전체 통합 diff. base=nil이면 HEAD 대비(현재 미커밋 전체),
    /// base 지정이면 세션 기준선 대비(이번 세션 전체 = 커밋+미커밋).
    case all(base: String?)

    var id: String {
        switch self {
        case .file(let change): return "f:\(change.path)"
        case .commit(let hash, _): return "c:\(hash)"
        case .all(let base): return "all:\(base ?? "HEAD")"
        }
    }

    var title: String {
        switch self {
        case .file(let change): return change.path
        case .commit(_, let subject): return subject
        case .all(let base): return base == nil ? "전체 변경" : "이번 세션 전체 변경"
        }
    }

    /// 탭 라벨(짧게).
    var tabTitle: String {
        switch self {
        case .file(let change): return basename(change.path)
        case .commit(let hash, _): return String(hash.prefix(7))
        case .all(let base): return base == nil ? "전체 변경" : "세션 전체"
        }
    }

    var tabIcon: String {
        switch self {
        case .file: return "plusminus"
        case .commit: return "clock"
        case .all: return "rectangle.stack"
        }
    }

    /// 여러 파일을 한 번에 훑는 통합 diff인지 — CodeHTML 파일 경계 sticky 헤더 여부.
    var isAggregate: Bool {
        if case .all = self { return true }
        return false
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
    /// canonical repo 루트(리뷰 코멘트 키) — 첫 load에서 1회 계산. nil이면 코멘트 비활성(git 저장소 아님).
    @State private var repoRoot: String?
    /// 코멘트 입력 시트 초안(줄의 '＋' 클릭으로 설정). nil이면 시트 닫힘.
    @State private var draft: CommentDraft?
    /// 나란히 보기(2열) 여부 — 도구줄 [통합 | 나란히] 토글. 기본은 통합. 뷰 로컬 상태.
    @State private var sideBySide = false

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                header
                HDivider()
            }
            toolbar
            if !loaded {
                centerLabel("불러오는 중…")
            } else if lines.isEmpty {
                centerLabel("변경 내용 없음")
            } else {
                CodeWebView(
                    html: CodeHTML.diff(lines: lines, dark: GhosttyRuntime.systemIsDark,
                                        stageable: hunkStageable, discardable: hunkStageable,
                                        aggregate: target.isAggregate,
                                        commentable: commentable && !sideBySide, comments: resolvedComments,
                                        sideBySide: sideBySide),
                    onMessage: hunkStageable ? { idx in Task { @MainActor in await stageHunk(idx) } } : nil,
                    onDiscard: hunkStageable ? { idx in Task { @MainActor in await discardHunk(idx) } } : nil,
                    onComment: (commentable && !sideBySide) ? handleComment : nil,
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
        .sheet(item: $draft) { d in
            ReviewCommentSheet(draft: d, onSubmit: { addComment(d, body: $0) }, onCancel: { draft = nil })
        }
    }

    // MARK: 리뷰 코멘트 — 줄 '＋'로 달고, lineText 재앵커링으로 라이브 리로드에도 따라간다.

    /// 코멘트를 달 수 있는 diff인지 — git 저장소이고(repoRoot 있음) 커밋 diff가 아닐 때(불변 이력엔 코멘트 안 함).
    private var commentable: Bool {
        guard repoRoot != nil else { return false }
        if case .commit = target { return false }
        return true
    }

    /// 저장된 코멘트를 현재 diff 줄에 재앵커링해 표시용으로 판다. 스토어(@Observable)를 body에서 읽어 변경에 반응.
    private var resolvedComments: [AnchoredComment] {
        guard commentable, let root = repoRoot else { return [] }
        return ReviewCommentAnchor.resolve(ReviewCommentStore.shared.comments(inRepo: root), lines: lines)
    }

    /// diff-viewer 브리지 메시지 처리 — add는 입력 시트를 띄우고, delete는 스토어에서 제거.
    private func handleComment(_ msg: ReviewBridgeMessage) {
        guard let root = repoRoot else { return }
        switch msg {
        case let .add(file, side, line, text):
            draft = CommentDraft(file: file, side: side, line: line, lineText: text)
        case let .delete(id):
            ReviewCommentStore.shared.delete(id: id, inRepo: root)
        }
    }

    private func addComment(_ d: CommentDraft, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let root = repoRoot, !trimmed.isEmpty {
            ReviewCommentStore.shared.add(file: d.file, side: d.side, line: d.line,
                                          lineText: d.lineText, body: trimmed, inRepo: root)
        }
        draft = nil
    }

    /// 절대 경로(repo dir + 상대경로). status의 opPath는 repo 루트 기준 상대경로다.
    private func absolutePath(_ rel: String) -> String {
        (dir as NSString).appendingPathComponent(rel)
    }

    /// 감시 대상 결정 — 파일 diff는 부모 디렉토리, 통합 diff는 워크트리 루트를 감시한다.
    /// 커밋 diff는 불변이라 감시하지 않는다(nil).
    private func fileWatcher() -> FileWatcher? {
        switch target {
        case .file(let initial):
            let abs = absolutePath(initial.opPath)
            return FileWatcher(path: (abs as NSString).deletingLastPathComponent)
        case .all:
            return FileWatcher(path: dir) // 워크트리 전체 — 아무 파일이나 바뀌면 재로드(git 패널과 같은 패턴)
        case .commit:
            return nil
        }
    }

    /// FSEvents는 부모 디렉토리 전체(재귀)를 알린다 → 재로드 판단.
    /// 스테이지 재적용 중(applying)이면 건너뛴다 — runStage 끝의 load()가 최신을 반영한다.
    private func reloadIfChanged() async {
        guard !applying else { return }
        switch target {
        case .file(let initial):
            // 이 파일 mtime이 실제 바뀐 경우만 재로드(FSEvents 재귀 소음·스테이지 무시).
            let abs = absolutePath(initial.opPath)
            let m = (try? FileManager.default.attributesOfItem(atPath: abs)[.modificationDate]) as? Date
            guard m != lastMTime else { return }
            await load()
        case .all:
            await load() // 워크트리 전체라 특정 파일 판별 없이 항상 재로드(0.3s 디바운스됨)
        case .commit:
            return
        }
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
            Image(systemName: "plusminus").font(.muxa(.body)).foregroundStyle(Color.pMuted)
            Text(target.title)
                .font(.muxaMono(.body, weight: .medium))
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
            .font(.muxa(.body))
            .foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// diff 위 도구줄 — 파일 diff면 [전체 스테이지/언스테이지/버리기](hunk 버튼은 HTML 안), 오른쪽엔
    /// 항상 [통합 | 나란히] 보기 토글. 표시할 내용이 있을 때만 그린다.
    @ViewBuilder
    private var toolbar: some View {
        let showToggle = loaded && !lines.isEmpty
        if fileChange != nil || showToggle {
            HStack(spacing: 8) {
                if let change = fileChange {
                    if change.worktree != " " {
                        toolbarButton("전체 스테이지", icon: "plus") { Task { await stageWholeFile(change) } }
                    }
                    if change.isStaged {
                        toolbarButton("언스테이지", icon: "minus") { Task { await unstageWholeFile(change) } }
                    }
                    toolbarButton("변경 버리기", icon: "trash", destructive: true) { discardFile(change) }
                }
                if let stageError {
                    Text(stageError)
                        .font(.muxa(.caption)).foregroundStyle(Color.pDanger).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if applying { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16) }
                if showToggle { viewModeToggle }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.pPanel)
            HDivider()
        }
    }

    /// [통합 | 나란히] 세그먼트 토글 — 선택 칸만 강조. WKWebView가 html 변화로 모드 전환을 재로드한다.
    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            segButton("통합", selected: !sideBySide) { sideBySide = false }
            segButton("나란히", selected: sideBySide) { sideBySide = true }
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.pBorder, lineWidth: 1))
    }

    private func segButton(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.muxa(.label))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(selected ? Color.pBtnActive : Color.clear)
                .foregroundStyle(selected ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
    }

    private func toolbarButton(_ title: String, icon: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.muxa(.caption, weight: .bold))
                Text(title).font(.muxa(.label))
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

    /// hunk 하나만 버리기 — 확인 후 패치를 워크트리에 reverse 적용(그 hunk만 인덱스 상태로 원복).
    /// hunkStageable(추적 파일의 언스테이지 수정)일 때만 노출되므로 통 diff·untracked·스테이지 뷰엔 오지 않는다.
    private func discardHunk(_ index: Int) async {
        guard let change = fileChange else { return }
        guard let patch = DiffPatch.patch(forHunk: index, in: DiffPatch.parse(lines)) else {
            stageError = "이 hunk는 버릴 수 없어요"
            return
        }
        guard DiscardConfirm.confirmHunk(fileName: basename(change.opPath)) else { return }
        await runStage { await GitService.applyReverse(patch: patch, in: dir) }
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
        if repoRoot == nil { repoRoot = await GitService.repoRoot(in: dir) } // 리뷰 코멘트 키(1회)
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
        case .all(let base):
            change = nil // 통합 diff는 개별 파일 스테이지 없음(집계 뷰)
            text = await GitService.worktreeDiff(base: base ?? "HEAD", in: dir)
        }
        lines = text.components(separatedBy: "\n")
        loaded = true
    }
}
