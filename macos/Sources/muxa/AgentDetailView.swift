import Bonsplit
import SwiftUI

/// 세션 상세가 가리키는 대상 — **내용이 아니라 탭**이다(YJ-7).
///
/// 목록을 복사해 담지 않는다. 스토어를 SSOT로 두면 에이전트가 더 일하는 동안
/// 열려 있는 탭이 그대로 따라간다.
struct AgentDetailTarget: Identifiable, Equatable {
    let tabId: TabID
    /// 그 세션의 제목(얼린 첫 프롬프트) — 서브탭 라벨은 짧게 두고 이건 화면 헤더가 쓴다.
    let title: String

    var id: String { "ref:\(tabId.uuid.uuidString)" }
}

/// **세션 상세** — 한 세션이 한 일을 정독하는 화면(YJ-7).
///
/// 패널과 역할을 나눈다: **패널은 곁눈질**(무엇이 새로 바뀌었나), **여기는 정독**(무엇을 왜 했나).
/// 어휘는 패널과 같고(git 글리프·안 봤음 굵기·폴더 그룹핑) **폭이 허락하는 열만** 다르다 —
/// 사용자가 두 모델을 배우지 않아도 되게.
///
/// 좁은 패널이 자리가 없어 못 실은 것을 여기서 싣는다:
/// **몇 번 만졌나**(에이전트가 헤맨 자리)와 **어느 지시로 그랬나**.
struct AgentDetailView: View {
    let target: AgentDetailTarget
    /// 그 탭의 수집 집합. **body에서 호출**하므로 스토어(@Observable) 변경에 반응한다.
    var setProvider: (TabID) -> AgentChangeSet?
    /// 그 세션이 도는 폴더 — 경로 라벨·git 조회의 기준.
    var root: String?
    /// 지금 오른쪽에 열려 있는 파일 — 사이드바 모드에서 그 행을 선택 표시한다.
    var selectedPath: String?
    /// 사이드바 모드(diff와 나란히) — 폭이 좁아 **지시·영역 여백**을 접는다.
    var compact: Bool = false
    var onOpenFile: (String) -> Void
    var onOpenURL: (URL) -> Void
    /// 변경 행 클릭 = diff. 패널과 **같은 대상**(`.baselineFile`)을 연다.
    var onOpenDiff: (GitDiffTarget) -> Void

    @State private var status: [String: Character] = [:]
    @State private var mtimes: [String: Date] = [:]
    @State private var tick = Date()

    private var set: AgentChangeSet? { setProvider(target.tabId) }

    var body: some View {
        Group {
            if let set, !(set.entries.isEmpty && set.references.isEmpty) {
                VStack(spacing: 0) {
                    header(set)
                    ScrollView { content(set) }
                }
            } else {
                EmptyState(icon: "square.dashed",
                           title: "아직 기록이 없습니다",
                           subtitle: "claude가 파일을 편집하거나 읽으면 여기 모입니다",
                           compact: true) { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) { await refresh() }
        .tick(every: 30, into: $tick)
        .onChange(of: tick) { _, _ in Task { await refresh() } }
    }

    // MARK: 헤더 — 이 세션이 무엇이었나

    private func header(_ set: AgentChangeSet) -> some View {
        HStack(spacing: Space.sm) {
            ClaudeMark(size: IconSize.inlineMark)
            Text(target.title)
                .font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Space.lg)
            // 기준선은 diff가 **무엇과 비교되는지**를 말한다. 모르면(그리고 좁으면) 침묵한다.
            if !compact, let base = set.baselineHead {
                Text("기준선 \(String(base.prefix(7)))")
                    .font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
            }
        }
        .panelBar(height: RowHeight.panelHeader)
    }

    // MARK: 두 영역 — 변경 / 참고

    @ViewBuilder
    private func content(_ set: AgentChangeSet) -> some View {
        // 넓은 화면이라 접지 않는다 — 상한은 좁은 패널의 사정이다.
        let group = AgentChangeDisplay.group(from: set, status: status, mtimes: mtimes,
                                             limit: Int.max)
        let folders = AgentChangeDisplay.changeFolders(rows: group.rows, root: root)
        let refFolders = AgentChangeDisplay.referenceFolders(from: set, root: root)
        let webs = AgentChangeDisplay.references(from: set, kind: .web)

        VStack(alignment: .leading, spacing: Space.groupGap) {
            if !folders.isEmpty {
                region("변경", count: group.rows.count, unread: group.unreadCount)
                ForEach(folders) { folder in
                    folderHeader(folder.label, count: folder.rows.count)
                    ForEach(folder.rows) { row in
                        changeRow(row, base: group.baseline)
                    }
                }
            }
            if !refFolders.isEmpty || !webs.isEmpty {
                region("참고", count: set.references.count, unread: 0)
                ForEach(refFolders) { folder in
                    folderHeader(folder.label, count: folder.files.count)
                    ForEach(folder.files, id: \.key) { ref in
                        refRow(title: basename(ref.value), context: ref.context,
                               icon: { AnyView(FileGlyph(path: ref.value)) }) { onOpenFile(ref.value) }
                    }
                }
                if !webs.isEmpty {
                    folderHeader("웹", count: webs.count, mono: false)
                    ForEach(webs, id: \.key) { ref in
                        refRow(title: shortURL(ref.value), context: ref.context, mono: true,
                               icon: { AnyView(Image(systemName: "globe")
                                   .font(.muxa(.label)).foregroundStyle(Color.pMuted)) }) {
                            if let url = URL(string: ref.value) { onOpenURL(url) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, Space.lg)
    }

    /// 영역 머리 — 이 화면의 두 덩어리를 가른다. 패널의 섹션보다 한 단 크다(정독하는 화면).
    private func region(_ title: String, count: Int, unread: Int) -> some View {
        HStack(spacing: Space.sm) {
            Text(title)
                .font(.muxa(compact ? .body : .title, weight: .semibold))
                .foregroundStyle(Color.pFg)
            CountBadge(count: count)
            if unread > 0 {
                Text("\(unread) 안 봄").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? Space.panelInset : Space.lg)
        .frame(height: RowHeight.toolbar)
    }

    private func folderHeader(_ label: String, count: Int, mono: Bool = true) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "folder")
                .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot)
            Text(label)
                .font(mono ? .muxaMono(.label, weight: .semibold) : .muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1).truncationMode(.head)
            CountBadge(count: count)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? Space.panelInset : Space.lg)
        .frame(height: RowHeight.tight)
        .padding(.top, Space.sm)
    }

    // MARK: 행

    /// 변경 한 줄 — 패널과 같은 어휘에 **횟수·지시** 두 열을 더한다.
    private func changeRow(_ row: AgentChangeRow, base: String?) -> some View {
        let rel = relative(row.path)
        let open = { onOpenDiff(.baselineFile(base: base ?? "HEAD", path: rel)) }
        return HStack(spacing: Space.sm) {
            switch row.mark {
            case .git(let code):
                GitStatusBadge(code: code, weight: row.isUnread ? .medium : .regular)
            case .committed:
                Image(systemName: "checkmark")
                    .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusSlot)
                    .accessibilityLabel("커밋됨")
            }
            // 파일명은 **항상 `pFg`** — 다 봤다고 목록이 회색으로 죽지 않게(안 봤음은 굵기가 말한다).
            GitFileLabel(path: rel, weight: row.isUnread ? .medium : .regular, tone: Color.pFg)
            Spacer(minLength: Space.md)
            // **여러 번 고친 파일 = 헤맨 자리.** 1회면 침묵한다(대부분의 행에 안 뜬다).
            if row.touchCount >= 2 {
                Text("×\(row.touchCount)")
                    .font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
            }
            GitFileTime(mtime: row.mtime, now: tick)
            // 이 화면의 값 — "어느 지시로 건드렸나". **사이드바 모드에선 접는다** —
            // 320pt에 넣으면 파일명을 밀어낸다(폭이 열을 정한다).
            if !compact, let context = row.context, !context.isEmpty {
                Text(context)
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(.horizontal, compact ? Space.sm : Space.lg)
        .frame(maxWidth: .infinity)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        // 지금 오른쪽에 열려 있는 파일 = 선택 채움(마스터-디테일의 기본 문법).
        .modifier(ListRowFill(selected: rel == selectedPath))
        .padding(.horizontal, Space.xs)
        .onTapGesture(perform: open)
        .accessibilityRow(label: changeLabel(row, rel: rel), activate: open)
    }

    private func refRow(title: String, context: String?, mono: Bool = false,
                        @ViewBuilder icon: () -> AnyView,
                        action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.sm) {
            icon().frame(width: IconSize.inlineMark)
            Text(title)
                .font(mono ? .muxaMono(.label) : .muxa(.body))
                .foregroundStyle(Color.pFg)
                .lineLimit(1).truncationMode(mono ? .tail : .middle)
                .layoutPriority(1)
            if !compact, let context, !context.isEmpty {
                Text(context)
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? Space.sm : Space.lg)
        .frame(maxWidth: .infinity)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        .modifier(ListRowFill())
        .padding(.horizontal, Space.xs)
        .onTapGesture(perform: action)
        .accessibilityRow(label: title + (context.map { ", \($0)" } ?? ""), activate: action)
    }

    /// VO가 읽을 이름 — 굵기·색은 스크린리더에 존재하지 않으므로 **말로** 한다.
    private func changeLabel(_ row: AgentChangeRow, rel: String) -> String {
        var parts = [basename(rel)]
        switch row.mark {
        case .git(let code): parts.append(GitStatusStyle.label(code))
        case .committed: parts.append("커밋됨")
        }
        if row.isUnread { parts.append("안 봄") }
        if row.touchCount >= 2 { parts.append("\(row.touchCount)번 만짐") }
        if let c = row.context, !c.isEmpty { parts.append(c) }
        return parts.joined(separator: ", ")
    }

    // MARK: 보조

    private func relative(_ absolute: String) -> String {
        guard let root else { return absolute }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return absolute.hasPrefix(prefix) ? String(absolute.dropFirst(prefix.count)) : absolute
    }

    /// 스킴을 걷어낸 URL — `https://`는 모든 행에 똑같이 붙어 정보량이 0이다.
    private func shortURL(_ raw: String) -> String {
        for prefix in ["https://", "http://"] where raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }

    /// git 상태·mtime을 이 세션의 폴더에서 읽는다. 탭이 열려 있는 동안만 도는 조회다.
    private func refresh() async {
        guard let root else { status = [:]; mtimes = [:]; return }
        var map: [String: Character] = [:]
        if let st = await GitService.status(in: root) {
            for change in st.changes {
                let abs = (root as NSString).appendingPathComponent(change.opPath)
                map[abs] = change.isUntracked ? "?" : (change.worktree != " " ? change.worktree : change.index)
            }
        }
        status = map

        let paths = Set(setProvider(target.tabId)?.entries.keys.map { $0 } ?? [])
        // stat은 메인을 막지 않게 떼어낸다.
        mtimes = await Task.detached(priority: .utility) {
            var times: [String: Date] = [:]
            for path in paths {
                times[path] = (try? FileManager.default
                    .attributesOfItem(atPath: path)[.modificationDate]) as? Date
            }
            return times
        }.value
    }
}

/// 파일 타입 아이콘(Material Icon Theme) — 탐색기와 **같은 세트**라 종류가 색으로 먼저 읽힌다.
private struct FileGlyph: View {
    let path: String

    var body: some View {
        Image(nsImage: FileIcon.image(for: FileNode(path: path, name: basename(path),
                                                    isDirectory: false)))
            .resizable().interpolation(.high)
            .frame(width: IconSize.inlineMark, height: IconSize.inlineMark)
    }
}
