import Foundation

/// 문서 diff의 양쪽 원문을 **어디서 가져올지**에 대한 판정 — 순수 함수(셸아웃은 경계가 한다).
///
/// diff는 "옛 내용"과 "새 내용" 두 문자열만 있으면 계산된다. 문제는 그 둘의 출처가 target마다
/// 다르다는 것이다: 미커밋 파일은 `HEAD` vs 디스크, 커밋 안 파일은 `부모 커밋` vs `그 커밋`.
/// 이 판정을 뷰에 흩어 놓으면 "커밋 diff인데 디스크를 읽는" 실수가 난다.
enum DocSide: Equatable {
    /// git 리비전에서 읽는다(`git show <rev>:<path>`).
    case revision(rev: String, path: String)
    /// 워크트리의 현재 파일을 읽는다.
    case worktree(path: String)
    /// 그쪽엔 파일이 없다(생성 또는 삭제) — 빈 문서로 취급한다.
    case empty
}

/// 한 target의 양쪽 출처.
struct DocDiffSource: Equatable {
    let old: DocSide
    let new: DocSide

    /// target → 출처 판정.
    ///
    /// **리네임은 옛 경로로 읽어야 한다** — 새 경로는 옛 리비전에 존재하지 않는다.
    /// 이걸 틀리면 "파일 전체가 새로 생긴 것"으로 보여 diff가 통째로 초록이 된다.
    static func resolve(_ target: GitDiffTarget) -> DocDiffSource? {
        switch target {
        case .file(let change):
            // 미커밋 변경 — 옛쪽은 HEAD, 새쪽은 디스크(워처가 라이브로 갱신한다).
            if change.isUntracked {
                return DocDiffSource(old: .empty, new: .worktree(path: change.opPath))
            }
            if change.badge == "D" {
                return DocDiffSource(old: .revision(rev: "HEAD", path: change.oldPath), new: .empty)
            }
            return DocDiffSource(old: .revision(rev: "HEAD", path: change.oldPath),
                                 new: .worktree(path: change.opPath))

        case .commitFile(let hash, let path, let oldPath):
            // 커밋 안 파일 — 양쪽 다 리비전. 디스크를 안 보므로 **원본이 사라져도 된다**.
            return DocDiffSource(old: .revision(rev: "\(hash)^", path: oldPath ?? path),
                                 new: .revision(rev: hash, path: path))

        case .commit, .all:
            // 여러 파일을 한 화면에 담는 집계 diff — 문서 모드 대상이 아니다.
            return nil
        }
    }
}

/// "변경" 서브탭 도구줄의 보기 모드 — [통합 | 나란히 | 문서].
///
/// **안 되는 버튼을 회색으로 두지 않는다**(DESIGN §7의 사촌: 모르면 침묵). 문서 모드가 불가능한
/// 대상에서는 세그 자체가 2개로 줄어든다 — 눌러도 안 되는 걸 보여주면 "왜 안 되지"를 매번 묻게 된다.
enum ChangesViewMode: String, CaseIterable, Identifiable {
    case unified = "통합"
    case sideBySide = "나란히"
    case document = "문서"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .unified: return "list.bullet.rectangle"
        case .sideBySide: return "rectangle.split.2x1"
        case .document: return "doc.richtext"
        }
    }

    /// 이 target에서 고를 수 있는 모드들. 통합·나란히는 **항상** 가능하다(모든 것의 폴백).
    static func available(for target: GitDiffTarget) -> [ChangesViewMode] {
        var modes: [ChangesViewMode] = [.unified, .sideBySide]
        if supportsDocument(target) { modes.append(.document) }
        return modes
    }

    /// 문서 모드 가능 여부 — **마크다운 파일 하나를 다루는 diff**일 때만.
    ///
    /// 집계 diff(`.commit`·`.all`)는 여러 파일을 세로로 이어 붙이는데, 렌더된 문서 여러 개를
    /// 잇는 건 별개 문제라 이번 범위 밖이다. 비-md는 렌더할 문법이 없다.
    static func supportsDocument(_ target: GitDiffTarget) -> Bool {
        guard let path = documentPath(target) else { return false }
        return isMarkdown(path)
    }

    /// 문서 모드가 그릴 파일 경로. 집계 diff면 nil.
    static func documentPath(_ target: GitDiffTarget) -> String? {
        switch target {
        case .file(let change): return change.opPath
        case .commitFile(_, let path, _): return path
        case .commit, .all: return nil
        }
    }

    /// 확장자 판정 — `FileViewTarget.kind`의 markdown 목록과 **같은 집합**을 쓴다
    /// (같은 파일이 한 화면에선 md로, 다른 화면에선 아니면 안 된다).
    static func isMarkdown(_ path: String) -> Bool {
        FileViewTarget(path: path).kind == .markdown
    }
}
