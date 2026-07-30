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

/// **참고 목록** — 에이전트가 읽기만 한 것들. 답하는 질문은 "뭘 봤나" 하나다.
///
/// 그래서 횟수·시각·순서 통계를 붙이지 않는다. 파일은 **일반 뷰어**로, URL은 **인앱 브라우저**로 연다
/// (여기서는 동작을 우리가 정하므로 `MarkdownLink.external`의 시스템 브라우저 경로와 다르다).
///
/// `Grep` 패턴·`WebSearch` 질의·`Bash` 명령은 애초에 수집하지 않는다 — 열 수 있는 대상이 아니라
/// 목록에 두면 "눌러도 안 되는 행"이 된다.
struct AgentReferencesView: View {
    let target: AgentReferencesTarget
    /// 그 탭의 수집 집합을 읽는다. **body에서 호출**하므로 스토어(@Observable)의 변경에 반응한다 —
    /// 내용을 복사해 담지 않고도 살아 움직인다.
    var setProvider: (TabID) -> AgentChangeSet?
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
        let files = AgentChangeDisplay.references(from: set, kind: .file)
        let webs = AgentChangeDisplay.references(from: set, kind: .web)
        VStack(alignment: .leading, spacing: 0) {
            if !files.isEmpty {
                section("열어본 파일", count: files.count)
                ForEach(files, id: \.key) { ref in
                    row(basename(ref.value), detail: parentDir(ref.value)) { onOpenFile(ref.value) }
                }
            }
            if !webs.isEmpty {
                section("웹", count: webs.count)
                ForEach(webs, id: \.key) { ref in
                    // 호스트를 흐리게 앞에 두고 나머지를 본문으로 — 파일 행의 "이름 먼저" 문법과 같은 태도.
                    row(ref.value, detail: nil, mono: true) {
                        if let url = URL(string: ref.value) { onOpenURL(url) }
                    }
                }
            }
        }
        .padding(.vertical, Space.sm)
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack(spacing: Space.sm) {
            Text(title).font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
            Text("\(count)")
                .font(.muxaMono(.micro, weight: .semibold)).foregroundStyle(Color.pMuted)
                .padding(.horizontal, Space.xs)
                .frame(minHeight: 15)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.pBtnHover))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .frame(height: RowHeight.tight)
        .padding(.top, Space.md)
    }

    private func row(_ title: String, detail: String?, mono: Bool = false,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.sm) {
            Text(title)
                .font(mono ? .muxaMono(.label) : .muxa(.body))
                .foregroundStyle(Color.pFg)
                .lineLimit(1).truncationMode(mono ? .tail : .middle)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.head)
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

    private func parentDir(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }
}
