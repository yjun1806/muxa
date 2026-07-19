import SwiftUI

/// 미커밋 변경 목록 — 리뷰 탭의 위쪽.
///
/// **스테이지됨/변경 구분도, 커밋도 없다.** muxa는 편집을 에이전트에게 맡기는 앱이라 사람이 커밋을
/// 조립할 이유가 없다(에이전트가 무엇을 바꿨는지 아는 쪽이 메시지도 더 잘 쓴다). 스테이징은 커밋을
/// 조립하는 수단이라 커밋이 빠지면 존재 이유가 함께 사라지고, 인덱스는 리뷰어가 쓸 일 없는 개념이다.
/// 굳이 사람이 커밋해야 하면 **바로 옆 칸 터미널**에서 하면 된다(muxa가 설치 명령을 주입만 하고
/// Enter는 사람이 누르게 하는 것과 같은 태도).
///
/// **"봤음" 체크도 없다.** 워킹트리는 살아 있어서 에이전트가 계속 고치는데, 표식을 blob에 묶으면
/// 대부분 지워진 채로 있고 안 지워진 건 수동으로 눌러 채워야 했다 — 값은 얇고 비용(행마다 아이콘,
/// 갱신마다 파일별 `git hash-object`)은 두꺼웠다. 대신 **변경 시각**을 단다: 클릭 없이 얻어지고
/// "방금 만진 게 뭐지"라는 실제 첫 질문에 답한다.
///
/// **버리기도 없다(D37).** 판정은 사람이 하되 **실행은 전부 에이전트가** 한다 — 패널에서 몰래
/// 되돌리면 에이전트는 자기가 쓴 코드가 아직 있다고 믿고 다음 턴을 그 위에 쌓는다(컨텍스트 어긋남).
/// 거부의 경로는 diff 줄에 코멘트를 달아 다음 턴 지시로 보내는 것이다.
struct GitChangesSection: View {
    let status: GitStatus
    let dir: String
    /// 파일별 마지막 변경 시각 — 상위가 status 갱신 때 함께 읽어 내려준다.
    var mtimes: [String: Date] = [:]
    /// 상대 시각 계산 기준(`TimelineView`가 흘려보낸 현재 시각).
    var now: Date = Date()

    var onOpenDiff: (GitDiffTarget) -> Void
    /// 일반 뷰어로 열기(md 렌더링·코드 하이라이트) — 절대 경로를 받는다.
    var onOpenInViewer: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if status.isClean {
                PanelLabel("변경 없음")
            } else {
                ForEach(status.changes) { fileRow($0) }
            }
        }
    }

    /// 섹션 머리 — 개수 + 리뷰 진행률 + 전체 diff 진입.
    private var toolbar: some View {
        HStack(spacing: Space.sm) {
            SectionLabel(title: "변경된 파일", count: status.changes.count)
            Spacer(minLength: 0)
            if !status.isClean {
                Button { onOpenDiff(.all(base: nil)) } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "rectangle.stack").font(.muxa(.caption, weight: .bold))
                        Text("전체 diff").font(.muxa(.label))
                    }
                    .foregroundStyle(Color.pFg)
                }
                .buttonStyle(.plain)
                .clickCursor()
                .help("변경 파일 전체를 한 화면에서 훑기")
            }
        }
        .panelBar()
    }


    /// 파일 행 — [상태문자][파일명·경로][변경 줄 수][뷰어][봤음].
    /// 좌클릭 = diff · 문서 아이콘 = 일반 뷰어(md 렌더링·코드 하이라이트).
    private func fileRow(_ change: GitFileChange) -> some View {
        let name = basename(change.opPath)
        return HStack(spacing: Space.sm) {
            Button { onOpenDiff(.file(change)) } label: {
                HStack(spacing: Space.sm) {
                    GitStatusBadge(code: change.badge)
                    GitFileLabel(path: change.opPath)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help(change.path)

            GitFileTime(mtime: mtimes[change.opPath], now: now)
            if canOpenInViewer(change) {
                GitViewerButton(name: name) { openInViewer(change.opPath) }
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .modifier(ListRowFill(selected: false))
        .contextMenu {
            Button("diff 보기") { onOpenDiff(.file(change)) }
            if canOpenInViewer(change) {
                Button("뷰어로 열기") { openInViewer(change.opPath) }
            }
        }
    }

    /// 삭제된 파일은 뷰어로 못 연다 — 디스크에 없다. diff에는 남아 있으니 그쪽으로만 보낸다.
    private func canOpenInViewer(_ change: GitFileChange) -> Bool {
        onOpenInViewer != nil && change.badge != "D"
    }

    private func openInViewer(_ rel: String) {
        onOpenInViewer?((dir as NSString).appendingPathComponent(rel))
    }
}
