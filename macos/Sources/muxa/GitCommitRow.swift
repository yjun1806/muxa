import SwiftUI

/// 커밋 한 줄 + 펼치면 그 커밋이 건드린 파일 목록.
///
/// **행 클릭 = 펼침이지 diff 열기가 아니다.** 예전엔 클릭이 곧바로 통짜 diff 서브탭을 열었는데,
/// 훑기(뭘 만졌나 — 1초)와 정독(diff 읽기 — 1분)이 **같은 제스처**를 공유하는 비대칭이었다.
/// 목록을 훑는 것만으로 서브탭이 쌓이고 사용자가 닫는 비용을 냈다. 이제 훑기는 인라인이,
/// 정독만 서브탭이 맡는다(우측 `⧉` · ⌥클릭 · `⏎`).
///
/// **소속은 선이 아니라 면이 그린다.** 펼친 파일 묶음은 `lane` 면 위에 앉는다 — 사이드바가
/// 프로젝트 레인으로 같은 문제를 이미 푼 문법이고, 동심원 규칙(레인 인셋 `xs` + 안쪽 행 `sm`
/// = 레인 `lg`)도 그대로다. 들여쓰기는 좁은 패널에서 경로 가로 공간을 뺏고, 가로 구분선은
/// 커밋 10개 × 파일 5개면 선이 50개가 그어져 "조용한 크롬"이 무너진다.
struct GitCommitRow: View {
    let commit: GitCommit
    let expanded: Bool
    /// 펼친 파일 목록. nil이면 아직 로딩 중(자리만 잡는다).
    let files: [GitCommitFile]?
    /// 지금 서브탭으로 열려 있는 (커밋, 파일) — 선택 채움 판정.
    var openPath: String?

    var onToggle: () -> Void
    var onOpenWholeDiff: () -> Void
    var onOpenFile: (GitCommitFile) -> Void
    /// 현재 워크트리에 그 파일이 남아 있으면 **지금 파일**을 뷰어로 연다(커밋 당시 내용이 아니다).
    /// nil을 돌려주면 아이콘을 안 그린다 — 그 뒤 지워진 파일엔 열 게 없다.
    var onOpenInViewer: ((GitCommitFile) -> (() -> Void)?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded { fileLane }
        }
    }

    /// 커밋 행 — 1줄이다. 2줄이면 같은 스크롤 안 파일 행(24)·섹션 헤더(22)와 리듬이 갈린다.
    /// 작성자는 hover 카드로 내렸다 — 대부분 사용자 자신이라 상시 표시할 값이 아니고,
    /// 그 자리를 변경 통계가 쓰는 게 밀도상 이득이다.
    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: Space.sm) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusSlot)

                Text(commit.subject)
                    .font(.muxa(.body))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: Space.xs)

                Text(commit.shortHash)
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
                Text(commit.date)
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)

                // 통짜 diff는 **상시 보이는** 아이콘으로. hover에만 두면 클릭 동작이 펼침으로
                // 바뀐 걸 알아챌 방법이 없다(기존 "클릭=diff" 근육기억 보호).
                IconButton(icon: "rectangle.stack", scale: .caption,
                           help: "커밋 전체 diff 열기",
                           label: "\(commit.subject) 전체 diff 열기", action: onOpenWholeDiff)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .modifier(ListRowFill(selected: false))
        // hover 카드를 붙이지 않는다 — 행에 이미 있는 제목·해시·시각을 그대로 반복하면서
        // 행 위에 겹쳐 떠서 정작 읽으려던 줄을 가렸다. 작성자는 단일 사용자 도구에서 정보량이 낮아
        // 접근성 라벨에만 남긴다.
        .accessibilityLabel("\(commit.subject), \(commit.author), \(commit.date)")
        .accessibilityHint(expanded ? "접으려면 누르세요" : "파일 내역을 보려면 누르세요")
    }

    /// 펼친 파일 묶음 — `lane` 면 위. 동심원: 레인 인셋 `Space.xs` + 안쪽 행 `Radius.sm` = `Radius.lg`.
    @ViewBuilder
    private var fileLane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let files {
                if files.isEmpty {
                    // 머지 커밋 등 — ✓를 지어내지 않는다.
                    Text("이 커밋은 파일을 바꾸지 않았습니다")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                        .padding(.horizontal, Space.sm)
                        .frame(height: RowHeight.tight, alignment: .leading)
                } else {
                    ForEach(files) { file in
                        GitCommitFileRow(
                            file: file,
                            selected: openPath == file.path,
                            onOpen: { onOpenFile(file) },
                            onOpenInViewer: onOpenInViewer?(file))
                    }
                }
            } else {
                // 비동기 로드는 **자리를 먼저 잡는다**(muxaHoverCard와 같은 규칙) —
                // 안 그러면 확장 애니메이션이 두 번 튄다.
                ForEach(0..<2, id: \.self) { _ in
                    Text("…")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                        .padding(.horizontal, Space.sm)
                        .frame(height: RowHeight.row, alignment: .leading)
                }
            }
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pLane, in: RoundedRectangle(cornerRadius: Radius.lg))
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.xs)
    }
}
