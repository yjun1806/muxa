import Bonsplit
import SwiftUI

/// 참고 목록이 가리키는 대상 — **내용이 아니라 탭**이다(YJ-7).
///
/// 목록을 복사해 담지 않는 이유: 수집은 계속 늘어난다. 스토어를 SSOT로 두면
/// 에이전트가 더 읽는 동안 열려 있는 탭이 그대로 따라간다.
struct AgentReferencesTarget: Identifiable, Equatable {
    let tabId: TabID
    /// 탭 라벨 — 그 세션의 제목(얼린 첫 프롬프트)을 그대로 쓴다.
    let title: String

    var id: String { "ref:\(tabId.uuid.uuidString)" }
}

/// **참고 목록** — 에이전트가 읽기만 한 것들. 답하는 질문은 "뭘 봤나"와 "왜 봤나" 둘이다.
///
/// 횟수·시각 통계는 붙이지 않는다. 대신 **폴더별로 묶고**(수십 개가 평평하면 어디를 봤는지 안 읽힌다),
/// 각 항목에 **그때의 지시**를 흐리게 단다(목록만으로는 "왜 이걸 봤지"가 안 풀린다).
///
/// 파일은 일반 뷰어로, URL은 인앱 브라우저로 연다. `Grep` 패턴·`WebSearch` 질의는 애초에
/// 수집하지 않는다 — 열 수 있는 대상이 아니라 목록에 두면 "눌러도 안 되는 행"이 된다.
struct AgentReferencesView: View {
    let target: AgentReferencesTarget
    /// 그 탭의 수집 집합을 읽는다. **body에서 호출**하므로 스토어(@Observable)의 변경에 반응한다.
    var setProvider: (TabID) -> AgentChangeSet?
    /// 저장소 루트 — 폴더 라벨을 여기 상대로 줄인다. 없으면 절대경로로 적는다.
    var root: String?
    var onOpenFile: (String) -> Void
    var onOpenURL: (URL) -> Void

    private var set: AgentChangeSet? { setProvider(target.tabId) }

    var body: some View {
        Group {
            if let set, !set.references.isEmpty {
                ScrollView { list(set) }
            } else {
                EmptyState(icon: "book",
                           title: "참고한 것이 없습니다",
                           subtitle: "claude가 파일을 읽거나 웹을 조회하면 여기 모입니다",
                           compact: true) { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }

    @ViewBuilder
    private func list(_ set: AgentChangeSet) -> some View {
        let folders = AgentChangeDisplay.referenceFolders(from: set, root: root)
        let webs = AgentChangeDisplay.references(from: set, kind: .web)
        // 그룹 사이는 선이 아니라 여백이 가른다 — 간격이 위계다(DESIGN §4).
        VStack(alignment: .leading, spacing: Space.groupGap) {
            ForEach(folders) { folder in
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(icon: "folder", label: folder.label, count: folder.files.count,
                                  mono: true)
                    ForEach(folder.files, id: \.key) { ref in
                        row(title: basename(ref.value), context: ref.context,
                            icon: { AnyView(FileGlyph(path: ref.value)) }) { onOpenFile(ref.value) }
                    }
                }
            }
            if !webs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(icon: "globe", label: "웹", count: webs.count, mono: false)
                    ForEach(webs, id: \.key) { ref in
                        row(title: shortURL(ref.value), context: ref.context, mono: true,
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

    /// 소섹션 머리글 — 폴더 경로는 모노(경로가 곧 신원이다, DESIGN §3).
    private func sectionHeader(icon: String, label: String, count: Int, mono: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icon)
                .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot)
            Text(label)
                .font(mono ? .muxaMono(.label, weight: .semibold) : .muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1).truncationMode(.head)
            Text("\(count)")
                .font(.muxaMono(.micro, weight: .semibold)).foregroundStyle(Color.pMuted)
                .padding(.horizontal, Space.xs)
                .frame(minWidth: 15, minHeight: 14)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.pBtnHover))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.tight)
        .padding(.bottom, Space.tight)
    }

    /// 한 줄 — 아이콘 · 이름 · **그때의 지시**(흐리게, 남는 폭만큼).
    private func row(title: String, context: String?, mono: Bool = false,
                     @ViewBuilder icon: () -> AnyView,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.sm) {
            icon().frame(width: IconSize.inlineMark)
            Text(title)
                .font(mono ? .muxaMono(.label) : .muxa(.body))
                .foregroundStyle(Color.pFg)
                .lineLimit(1).truncationMode(mono ? .tail : .middle)
                .layoutPriority(1)   // 이름이 먼저 자리를 잡고, 맥락이 남는 폭을 쓴다
            if let context, !context.isEmpty {
                Text(context)
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.row)
        .contentShape(Rectangle())
        .modifier(ListRowFill())
        .padding(.horizontal, Space.xs)
        .onTapGesture(perform: action)
    }

    /// 스킴을 걷어낸 URL — `https://`는 모든 행에 똑같이 붙어 정보량이 0이다.
    private func shortURL(_ raw: String) -> String {
        for prefix in ["https://", "http://"] where raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }
}

/// 파일 타입 아이콘(Material Icon Theme) — 탐색기와 **같은 세트**라 파일 종류가 색으로 먼저 읽힌다.
private struct FileGlyph: View {
    let path: String

    var body: some View {
        Image(nsImage: FileIcon.image(for: FileNode(path: path, name: basename(path),
                                                    isDirectory: false)))
            .resizable().interpolation(.high)
            .frame(width: IconSize.inlineMark, height: IconSize.inlineMark)
    }
}
