import SwiftUI

/// 변경 줄 수 표시(`+12 −3`) — 커밋 행·파일 행이 공유.
///
/// **숫자다, 막대가 아니다.** GitHub식 5칸 블록은 좁은 행 우측에서 해시·시간과 자리를 다투는데
/// 정보량은 "대략 얼마나 크냐" 하나뿐이다(밀도 우선 원칙에 반한다). `Meter`도 아니다 — 그건
/// 0~1 비율 **하나**를 그리는 단일값 게이지라 두 절대량을 담는 의미가 아니다.
///
/// **색은 글자에만, 면은 없다.** `brand`가 "면이 아니라 선·글리프로만"인 것의 git판이다.
/// 배경 틴트를 주는 순간 "색은 아껴 쓴다" 예산이 터진다.
struct GitDiffStat: View {
    let added: Int?
    let deleted: Int?
    var binary: Bool = false

    var body: some View {
        // **모르면 침묵한다** — 바이너리·짝 못 찾음은 아무것도 안 붙인다("—"도 지어내지 않는다).
        if binary || (added == nil && deleted == nil) {
            EmptyView()
        } else {
            HStack(spacing: Space.xs) {
                if let added, added > 0 {
                    Text("+\(added)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color(nsColor: Palette.gitAdded))
                }
                if let deleted, deleted > 0 {
                    Text("−\(deleted)")
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color(nsColor: Palette.gitDeleted))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(added ?? 0)줄 추가, \(deleted ?? 0)줄 삭제")
        }
    }
}

/// git 상태 표식 — GitHub식 diff 글리프(사각형 안의 `+`·`·`·`−`·`→`).
///
/// 문자(`A`/`M`/`D`) 대신 도형을 쓰는 이유는 `GitStatusStyle`에 적어뒀다(요약: PR "Files changed"의
/// 관례라 학습 비용이 0이고, 목록을 훑을 때 글자는 읽어야 하지만 도형은 안 읽어도 보인다).
/// 폭은 `IconSize.statusSlot` — 사이드바 트리와 같은 정사각 슬롯이라 두 단의 텍스트가 같은
/// 세로선에서 시작한다.
struct GitStatusBadge: View {
    let code: Character

    var body: some View {
        Image(systemName: GitStatusStyle.glyph(code))
            .font(.muxa(.label))
            .foregroundStyle(GitStatusStyle.color(code))
            .frame(width: IconSize.statusSlot)
            .accessibilityLabel(GitStatusStyle.label(code))
    }
}

/// 파일이 마지막으로 바뀐 시각 — 미커밋 변경 행의 꼬리표("3m").
///
/// 에이전트가 여러 파일을 훑고 지나간 뒤 **"방금 만진 게 뭐지"**가 리뷰의 첫 질문이라, 목록에서
/// 최신 변경을 바로 짚을 수 있어야 한다. 커밋 행이 상대 시각을 다는 것과 같은 문법(`muxaMono`)이다.
///
/// **모르면 침묵한다** — mtime을 못 읽으면(삭제된 파일 등) 아무것도 안 그린다.
struct GitFileTime: View {
    let mtime: Date?
    let now: Date

    var body: some View {
        if let mtime {
            Text(RelativeTime.compact(now.timeIntervalSince(mtime)))
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .accessibilityLabel("\(RelativeTime.compact(now.timeIntervalSince(mtime))) 전에 변경됨")
        }
    }
}

/// 파일 이름 + 부모 경로 — 목록 행의 본문.
///
/// **파일명 우선, 경로는 흐리게 뒤에.** 좁은 패널에서 검증된 배치다(VSCode SCM·GitHub Desktop).
/// 자르는 방향이 서로 다른 게 핵심이다: 파일명은 꼬리를 자르면 확장자가 사라지므로 **가운데**를,
/// 경로는 깊이보다 직속 디렉터리가 정보량이 크므로 **머리**를 자른다.
struct GitFileLabel: View {
    let path: String
    /// 리네임 원본 — 있으면 "옛이름 → " 접두가 붙는다.
    var oldPath: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(basename(path))
                .font(.muxa(.body))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(.middle)
            if let parent = parentDir(path), !parent.isEmpty {
                Text(parent)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private func parentDir(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }
}

/// 커밋 안 파일 한 줄 — 상태 문자 · 파일명 · 경로 · 변경 줄 수 · 리뷰 체크.
///
/// 변경사항의 `GitFileChange` 행과 **같은 문법**을 쓰되 쓰기 동작(스테이지·버리기)이 없다.
/// 이미 커밋된 사실이라 이 화면에서 바뀌지 않는다.
struct GitCommitFileRow: View {
    let file: GitCommitFile
    /// 지금 서브탭으로 열려 있는 파일인지 — 선택 채움.
    var selected: Bool = false
    var onOpen: () -> Void
    /// 일반 뷰어로 열기. **그 파일이 지금도 워크트리에 있을 때만** 값이 있다 —
    /// 커밋 당시 내용이 아니라 **현재 파일**을 여는 것이라, 그 뒤 지워졌으면 열 게 없다.
    var onOpenInViewer: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: onOpen) {
                HStack(spacing: Space.sm) {
                    GitStatusBadge(code: file.status)
                    GitFileLabel(path: file.path, oldPath: file.oldPath)
                    Spacer(minLength: Space.xs)
                    GitDiffStat(added: file.added, deleted: file.deleted, binary: file.isBinary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)

            if let onOpenInViewer {
                GitViewerButton(name: basename(file.path), action: onOpenInViewer)
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.row)
        .modifier(ListRowFill(selected: selected))
        .contextMenu {
            Button("이 커밋의 diff 보기", action: onOpen)
            if let onOpenInViewer {
                Button("현재 파일을 뷰어로 열기", action: onOpenInViewer)
            }
        }
    }
}

/// 일반 뷰어로 열기 버튼 — 파일 행 우측.
///
/// diff는 "무엇이 바뀌었나"를 말하고 뷰어는 "**지금 이게 어떤 모습인가**"를 말한다. 에이전트가 쓴
/// README·설계 문서는 `+`/`−` 조각으로 읽으면 형태가 안 잡힌다 — md는 렌더링해서, 코드는 하이라이트해서
/// 통째로 보는 게 맞다. 그래서 숨은 제스처(⌥클릭)가 아니라 **상시 아이콘**으로 낸다.
struct GitViewerButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        IconButton(icon: "doc.text.magnifyingglass", scale: .caption,
                   help: "뷰어로 열기 — 렌더링된 문서·하이라이트된 코드",
                   label: "\(name) 뷰어로 열기", action: action)
    }
}

