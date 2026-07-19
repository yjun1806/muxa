import SwiftUI

/// 커밋 목록 — 펼침·파일 내역·기준선 마커. **리뷰 탭과 히스토리 탭이 공유한다**
/// (같은 정보는 어디서 보든 같은 모양이어야 재학습이 없다).
/// 상태를 소유하지 않는다 — 값과 클로저만 받는다(controlled).
struct GitCommitList: View {
    let commits: [GitCommit]
    /// 지금 펼친 커밋 해시(아코디언 — 하나만).
    let expanded: String?
    /// 해시 → 파일 목록 캐시. 값이 없으면 로딩 중(행이 자리를 잡는다).
    let files: [String: [GitCommitFile]]
    /// 기준선 해시 — 이 커밋 **위에** "이번 작업 시작" 마커를 그린다. nil이면 안 그린다.
    var baseline: String?
    var onToggle: (GitCommit) -> Void
    var onOpenDiff: (GitDiffTarget) -> Void
    /// 커밋 파일 → 일반 뷰어로 열기. 지금 워크트리에 없으면 nil(아이콘 미표시).
    var onOpenInViewer: ((GitCommitFile) -> (() -> Void)?)?

    var body: some View {
        ForEach(commits) { commit in
            // 기준선 마커 — "여기부터가 이번 작업"이 보여야 리셋 버튼의 결과가 예측 가능해진다.
            if let baseline, commit.hash == baseline {
                baselineMarker
            }
            GitCommitRow(
                commit: commit,
                expanded: expanded == commit.hash,
                files: files[commit.hash],
                openPath: nil,
                onToggle: { onToggle(commit) },
                onOpenWholeDiff: { onOpenDiff(.commit(hash: commit.hash, subject: commit.subject)) },
                onOpenFile: { file in
                    onOpenDiff(.commitFile(hash: commit.hash, path: file.path, oldPath: file.oldPath))
                },
                onOpenInViewer: onOpenInViewer)
        }
    }

    /// 기준선 구분선 — **무채로 둔다.** 스크롤할 때마다 지나가는 선에 브랜드 버밀리언을 쓰면
    /// "크롬 픽셀 1% 미만" 예산에 안 맞는다.
    private var baselineMarker: some View {
        HStack(spacing: Space.sm) {
            Rectangle().fill(Color.pBorder).frame(height: RowHeight.hairline)
            Text("이번 작업 시작")
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted)
                .fixedSize()
            Rectangle().fill(Color.pBorder).frame(height: RowHeight.hairline)
        }
        .padding(.horizontal, Space.panelInset)
        .frame(height: RowHeight.tight)
    }
}

/// 리뷰 탭 — 미커밋 + 이번 작업 커밋이 **한 스크롤**에.
///
/// 실제 리뷰 흐름은 `미커밋 훑기 → 커밋 → 방금 커밋 확인 → 다시 미커밋`이라 두 정보가 한 화면에
/// 있어야 한다(예전엔 그 사이마다 탭을 클릭했다). 덤으로 "전체 diff" 버튼의 범위(커밋+미커밋)와
/// 목록의 범위가 비로소 일치한다.
struct GitReviewTab: View {
    let status: GitStatus?
    let dir: String?
    let loaded: Bool
    let sessionBase: String?
    let sessionCommits: [GitCommit]
    /// 파일별 마지막 변경 시각 + 상대시각 기준.
    let mtimes: [String: Date]
    let now: Date

    let commitList: GitCommitList
    var onResetBaseline: () -> Void
    var onOpenDiff: (GitDiffTarget) -> Void
    var onOpenInViewer: ((String) -> Void)?

    var body: some View {
        if let status {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GitChangesSection(
                        status: status, dir: dir ?? "", mtimes: mtimes, now: now,
                        onOpenDiff: onOpenDiff, onOpenInViewer: onOpenInViewer)
                    HDivider()
                    sessionSection
                }
                .padding(.bottom, Space.md)
            }
        } else {
            PanelLabel("불러오는 중…")
        }
    }

    /// 기준선 이후 커밋 — "이번 작업에서 에이전트가 커밋한 것".
    @ViewBuilder
    private var sessionSection: some View {
        HStack(spacing: Space.sm) {
            SectionLabel(title: "이번 작업에서 커밋함", count: sessionCommits.count)
            Spacer(minLength: 0)
            if let base = sessionBase, !sessionCommits.isEmpty {
                Button { onOpenDiff(.all(base: base)) } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "rectangle.stack").font(.muxa(.caption, weight: .bold))
                        Text("전체").font(.muxa(.label))
                    }
                    .foregroundStyle(Color.pFg)
                }
                .buttonStyle(.plain).clickCursor()
                .help("이번 작업 전체(커밋 + 미커밋)를 한 화면에서 훑기")
            }
            Button(action: onResetBaseline) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.circle").font(.muxa(.caption))
                    Text("여기까지 봤음").font(.muxa(.caption))
                }
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted)
            .help("기준선을 현재 HEAD로 리셋 — 이후 커밋만 '이번 작업'에 표시")
            .disabled(sessionBase == nil)
        }
        .panelBar()

        if sessionBase == nil {
            PanelLabel("이번 작업 시작 지점을 잡는 중…")
        } else if sessionCommits.isEmpty {
            PanelLabel(loaded ? "이번 작업에서 커밋한 게 없습니다" : "불러오는 중…")
        } else {
            commitList
        }
    }
}

/// 히스토리 탭 — 저장소가 걸어온 길. 리뷰 탭과 같은 커밋 행 문법을 쓰고 기준선 마커가 붙는다.
struct GitHistoryTab: View {
    let commits: [GitCommit]
    let loaded: Bool
    let commitList: GitCommitList

    var body: some View {
        if commits.isEmpty {
            // 이유를 지어내지 않는다 — subtitle 없음.
            PanelLabel(loaded ? "아직 커밋이 없습니다" : "불러오는 중…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    commitList
                }
                .padding(.vertical, Space.xs)
            }
        }
    }
}
