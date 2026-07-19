import SwiftUI

/// diff를 열 대상 — 변경 파일·커밋·워크트리 전체. .sheet(item:)용 Identifiable.
enum GitDiffTarget: Identifiable {
    case file(GitFileChange)
    case commit(hash: String, subject: String)
    /// 커밋 안 **파일 하나**의 diff — 커밋을 펼쳐 파일 행을 클릭했을 때.
    /// `.commit`(통짜)과 갈라 두는 이유: 리뷰는 파일 단위로 읽고, 좁은 패널에서 20파일 커밋의
    /// 통짜 diff를 여는 건 "훑기"가 아니라 "정독 강요"다. 리네임은 옛 경로가 있어야 diff가 안 빈다.
    case commitFile(hash: String, path: String, oldPath: String? = nil)
    /// 워크트리 전체 통합 diff. base=nil이면 HEAD 대비(현재 미커밋 전체),
    /// base 지정이면 세션 기준선 대비(이번 세션 전체 = 커밋+미커밋).
    case all(base: String?)

    var id: String {
        switch self {
        case .file(let change): return "f:\(change.path)"
        case .commit(let hash, _): return "c:\(hash)"
        // 해시와 경로가 **둘 다** 들어가야 한다 — 같은 파일을 여러 커밋에서 열면 탭이 서로 덮어쓴다.
        case .commitFile(let hash, let path, _): return "cf:\(hash):\(path)"
        case .all(let base): return "all:\(base ?? "HEAD")"
        }
    }

    var title: String {
        switch self {
        case .file(let change): return change.path
        case .commit(_, let subject): return subject
        case .commitFile(let hash, let path, _): return "\(path) · \(String(hash.prefix(7)))"
        case .all(let base): return base == nil ? "전체 변경" : "이번 작업 전체 변경"
        }
    }

    /// 탭 라벨(짧게).
    var tabTitle: String {
        switch self {
        case .file(let change): return basename(change.path)
        case .commit(let hash, _): return String(hash.prefix(7))
        // 파일명만 — 어느 커밋인지는 제목(`title`)·툴팁이 말한다. 좁은 탭에 해시까지 넣으면 둘 다 잘린다.
        case .commitFile(_, let path, _): return basename(path)
        case .all(let base): return base == nil ? "전체 변경" : "이번 작업 전체"
        }
    }

    var tabIcon: String {
        switch self {
        case .file: return "plusminus"
        case .commit: return "clock"
        // 커밋 안 파일 — 시계(커밋)와 plusminus(워크트리 변경) 사이. 과거의 한 파일이다.
        case .commitFile: return "clock.arrow.circlepath"
        case .all: return "rectangle.stack"
        }
    }

    /// 커밋에 속한 불변 diff인지 — 디스크 감시(FileWatcher)를 걸지 않고, 스테이지·버리기 같은
    /// 쓰기 동작도 띄우지 않는다. 이미 커밋된 사실은 이 화면에서 바뀌지 않는다.
    var isCommitted: Bool {
        switch self {
        case .commit, .commitFile: return true
        case .file, .all: return false
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
    /// 보기 모드 — [통합 | 나란히 | 문서]. 문서는 md에서만 뜬다.
    @State private var viewMode: ChangesViewMode = .unified
    /// 문서 모드 표시 밀도(Word 3단).
    @State private var density: DocDiffDensity = .full
    /// 문서 모드가 쓸 양쪽 원문. 문서 모드로 들어갈 때만 읽는다(안 쓰면 셸아웃 낭비).
    @State private var docOld: String?
    @State private var docNew: String?
    /// 문서 diff 계산 결과 — 실패하면 통합 뷰로 자동 강등한다(에러 화면을 만들지 않는다).
    @State private var docResult: DocDiffResult?

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                header
                HDivider()
            }
            toolbar
            if viewMode == .document {
                documentBody
            } else if !loaded {
                centerLabel("불러오는 중…")
            } else if lines.isEmpty {
                centerLabel("변경 내용 없음")
            } else {
                CodeWebView(
                    html: CodeHTML.diff(lines: lines, dark: GhosttyRuntime.systemIsDark,
                                        stageable: false, discardable: false,
                                        aggregate: target.isAggregate,
                                        commentable: commentable && !sideBySide, comments: resolvedComments,
                                        sideBySide: sideBySide),
                    onMessage: nil, // 헝크 스테이지 제거 — 조립할 커밋이 없다
                    onDiscard: nil, // 거부는 리뷰 코멘트로 — 에이전트가 직접 되돌린다
                    onComment: (commentable && !sideBySide) ? handleComment : nil,
                    busy: applying
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) {
            // 대상이 바뀌면 모드를 되돌린다 — md에서 문서 모드였다가 .swift로 옮기면 갈 곳이 없다.
            if !ChangesViewMode.available(for: target).contains(viewMode) { viewMode = .unified }
            docOld = nil; docNew = nil; docResult = nil
            await load()
            watcher = fileWatcher() // 파일 diff면 부모 디렉토리 감시 시작(커밋 diff는 nil)
        }
        .task(id: "\(target.id)|\(viewMode.rawValue)") {
            if viewMode == .document { await loadDocumentSources() }
        }
        .onChange(of: watcher?.changeSeq) { _, _ in Task { await reloadIfChanged() } }
        .sheet(item: $draft) { d in
            ReviewCommentSheet(draft: d, onSubmit: { addComment(d, body: $0) }, onCancel: { draft = nil })
        }
    }

    // MARK: 문서 모드

    /// 문서 diff 본문. 원문을 아직 못 읽었으면 자리를 잡고, 계산이 실패하면 **통합 뷰로 강등**한다
    /// (GitHub은 여기서 에러만 띄우고 사용자에게 수동 전환을 시켜 3년째 욕먹는다).
    @ViewBuilder
    private var documentBody: some View {
        if let r = docResult, let msg = r.failure {
            VStack(spacing: Space.sm) {
                Text("문서 보기를 만들지 못해 통합 보기로 표시합니다")
                    .font(.muxa(.body)).foregroundStyle(Color.pFg)
                Text(msg).font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { viewMode = .unified }
        } else if let old = docOld, let new = docNew {
            DocDiffWebView(
                oldSource: old, newSource: new,
                dark: GhosttyRuntime.systemIsDark,
                density: density,
                onComment: commentable ? handleComment : nil,
                onResult: { docResult = $0 })
        } else {
            centerLabel("문서를 여는 중…")
        }
    }

    /// 양쪽 원문을 읽어 온다 — 판정은 `DocDiffSource`(순수), 읽기는 여기(경계).
    private func loadDocumentSources() async {
        guard let src = DocDiffSource.resolve(target) else {
            docResult = DocDiffResult(failure: "이 대상은 문서 보기를 지원하지 않습니다")
            return
        }
        async let o = read(src.old)
        async let n = read(src.new)
        let (oldText, newText) = await (o, n)
        guard !Task.isCancelled else { return }
        docOld = oldText
        docNew = newText
    }

    private func read(_ side: DocSide) async -> String {
        switch side {
        case .empty:
            return ""
        case .revision(let rev, let path):
            return await GitService.fileAtRevision(rev: rev, path: path, in: dir)
        case .worktree(let path):
            return (try? String(contentsOfFile: absolutePath(path), encoding: .utf8)) ?? ""
        }
    }

    // MARK: 리뷰 코멘트 — 줄 '＋'로 달고, lineText 재앵커링으로 라이브 리로드에도 따라간다.

    /// 코멘트를 달 수 있는 diff인지 — git 저장소이면(repoRoot 있음) 언제나 가능하다.
    ///
    /// **커밋 diff에도 단다.** 예전엔 "불변 이력엔 코멘트 안 함"이라 막았는데, muxa의 코멘트는
    /// 이력을 고치는 게 아니라 **다음 턴 지시**다(터미널에 주입돼 에이전트가 읽는다). 에이전트
    /// 산출물의 주 단위가 커밋인데 거기서 리뷰 동선이 끊기면 "보고→코멘트→보냄"이 반쪽이 된다.
    private var commentable: Bool { repoRoot != nil }

    /// 이 diff가 속한 커밋 해시 — 코멘트의 스코프 키. 워크트리 diff면 nil.
    private var commentScope: String? {
        switch target {
        case .commit(let hash, _): return hash
        case .commitFile(let hash, _, _): return hash
        case .file, .all: return nil
        }
    }

    /// 저장된 코멘트를 현재 diff 줄에 재앵커링해 표시용으로 판다. 스토어(@Observable)를 body에서 읽어 변경에 반응.
    /// **스코프가 같은 것만** 판다 — 커밋 코멘트가 워크트리 diff에 새어나오지 않게(그 반대도).
    private var resolvedComments: [AnchoredComment] {
        guard commentable, let root = repoRoot else { return [] }
        let scoped = ReviewCommentStore.shared.comments(inRepo: root, commit: commentScope)
        return ReviewCommentAnchor.resolve(scoped, lines: lines)
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
                                          lineText: d.lineText, body: trimmed, inRepo: root,
                                          commit: commentScope)
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
        case .commit, .commitFile:
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
        case .commit, .commitFile:
            return
        }
    }

    /// diff 대상이 변경 파일일 때만 값이 있다(.commit은 읽기 전용). load()가 최신 status로 채운다.
    private var fileChange: GitFileChange? {
        if case .file = target { return change }
        return nil
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

    /// diff 위 도구줄 — [통합 | 나란히 | 문서] 보기 + 문서 모드의 밀도. **쓰기 버튼은 없다**(D37).
    /// 거부는 줄에 코멘트를 달아 에이전트에게 보낸다.
    @ViewBuilder
    private var toolbar: some View {
        let showToggle = viewMode == .document || (loaded && !lines.isEmpty)
        if fileChange != nil || showToggle {
            HStack(spacing: 8) {
                if viewMode == .document, let r = docResult, r.ok {
                    docStats(r)
                }
                if let stageError {
                    Text(stageError)
                        .font(.muxa(.caption)).foregroundStyle(Color.pDanger).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if applying { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16) }
                if viewMode == .document { densityToggle }
                if showToggle { viewModeToggle }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.pPanel)
            HDivider()
        }
    }

    /// 보기 토글 — **가능한 모드만 그린다.** 안 되는 버튼을 회색으로 두면 "왜 안 되지"를 매번 묻게 된다.
    private var viewModeToggle: some View {
        let modes = ChangesViewMode.available(for: target)
        return HStack(spacing: 0) {
            ForEach(modes) { m in
                segButton(m.rawValue, selected: isSelected(m)) { select(m) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
    }

    /// 문서 모드 밀도 — [최종본 | 위치만 | 상세]. 리뷰에 필요한 건 "결과물이 어떤 모습인가"와
    /// "뭘 건드렸나" 둘 다인데, 지금까지의 diff는 후자만 줬다.
    private var densityToggle: some View {
        HStack(spacing: 0) {
            ForEach(DocDiffDensity.allCases) { d in
                segButton(d.label, selected: density == d) { density = d }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
    }

    /// 변경 요약 — 스크롤 시작 전에 규모를 안다.
    private func docStats(_ r: DocDiffResult) -> some View {
        HStack(spacing: Space.sm) {
            if r.inserted > 0 { statChip("+\(r.inserted)", Palette.gitAdded) }
            if r.modified > 0 { statChip("~\(r.modified)", Palette.gitModified) }
            if r.deleted > 0 { statChip("−\(r.deleted)", Palette.gitDeleted) }
            if r.totalChanges == 0 {
                Text("변경 없음").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            if !r.highlight {
                // 정직한 강등 — 왜 밋밋한지 말해준다.
                Text("인라인 강조 미지원 macOS")
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
        }
    }

    private func statChip(_ text: String, _ color: NSColor) -> some View {
        Text(text).font(.muxaMono(.caption)).foregroundStyle(Color(nsColor: color))
    }

    private func isSelected(_ m: ChangesViewMode) -> Bool {
        switch m {
        case .unified: return viewMode != .document && !sideBySide
        case .sideBySide: return viewMode != .document && sideBySide
        case .document: return viewMode == .document
        }
    }

    private func select(_ m: ChangesViewMode) {
        switch m {
        case .unified: viewMode = .unified; sideBySide = false
        case .sideBySide: viewMode = .unified; sideBySide = true
        case .document: viewMode = .document
        }
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
        .clickCursor()
    }

    private func toolbarButton(_ title: String, icon: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.muxa(.caption, weight: .bold))
                Text(title).font(.muxa(.label))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .foregroundStyle(destructive ? Color(nsColor: Palette.gitDeleted) : Color.pFg)
        .disabled(applying)
    }

    // MARK: 스테이지 액션 — 성공 시 diff를 다시 읽는다(git 패널은 FSEvents로 자동 갱신).






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
        case .commitFile(let hash, let path, let oldPath):
            change = nil // 커밋된 파일은 스테이지·버리기 대상이 아니다(불변 사실)
            text = await GitService.commitFileDiff(hash: hash, path: path, oldPath: oldPath, in: dir)
        case .all(let base):
            change = nil // 통합 diff는 개별 파일 스테이지 없음(집계 뷰)
            text = await GitService.worktreeDiff(base: base ?? "HEAD", in: dir)
        }
        lines = text.components(separatedBy: "\n")
        loaded = true
    }
}
