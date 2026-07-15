import Foundation

/// 워크트리 ↔ 프로젝트 소속 판정(순수). 결정·근거는 ARCHITECTURE D31.
///
/// 두 물음을 값으로 답한다 — 부작용(Project 추가·서피스 재부모화)은 경계(AppState)가 진다.
///  1. `WorktreePromotion.pending`: 사이드바에 아직 없는 워크트리는? (감지·승격)
///  2. `WorktreeMove.target`: 이 탭의 cwd가 소속과 다른 워크트리에 들어가 있나? (이동 배지)
///
/// **`cd`는 소속을 바꾸지 않는다** — 여기 판정은 "표시/제안"의 재료일 뿐, 소속을 자동으로 옮기지 않는다.

/// 워크스페이스에 아직 Project로 없는 워크트리 — 사이드바에 세울 승격 후보.
enum WorktreePromotion {
    /// bare·메인 워크트리는 제외한다(bare=체크아웃 없음, 메인=이미 워크스페이스 그 자체).
    /// 메인 제외는 `isMain`으로 한다 — 워크스페이스 경로가 nil(초기=프로세스 cwd)이어도 견고하다.
    /// 이미 어떤 프로젝트의 실효 경로(`project.path ?? workspace.path`)와 같은 워크트리도 후보가 아니다.
    static func pending(worktrees: [GitWorktree], in workspace: Workspace) -> [GitWorktree] {
        let covered = Set(workspace.projects.compactMap { ($0.path ?? workspace.path).map(normalizePath) })
        return worktrees.filter { !$0.isBare && !$0.isMain && !covered.contains(normalizePath($0.path)) }
    }

    /// 인박스에 "추가?"로 띄울 워크트리 — `pending`이면서 **baseline에도 없는** 것.
    /// baseline(`workspace.acknowledgedWorktreePaths`) = 사용자가 이미 처리(추가/무시)한 경로. 영속이라
    /// 재시작해도 다시 조르지 않고, 무시했던 것이 되살아나지 않는다(orca의 externalWorktreeInboxBaseline 이식).
    static func offers(worktrees: [GitWorktree], in workspace: Workspace) -> [GitWorktree] {
        let ack = Set((workspace.acknowledgedWorktreePaths ?? []).map(normalizePath))
        return pending(worktrees: worktrees, in: workspace).filter { !ack.contains(normalizePath($0.path)) }
    }
}

/// 탭의 런타임 cwd가 소속 Project와 **다른** 워크트리에 들어가 있으면, 그 워크트리를 이동 대상으로 준다.
enum WorktreeMove {
    /// cwd를 포함하는 워크트리 중 **가장 깊은 것**을 고른다(중첩은 드물지만 안전하게). 매칭이 없으면 nil.
    /// 그게 이미 소속 경로(`projectPath`)와 같으면 nil — 이미 거기 있으니 옮길 게 없다.
    /// `projectPath`는 탭이 속한 프로젝트의 실효 경로(`project.path ?? workspace.path`)다.
    static func target(cwd: String?, projectPath: String?, worktrees: [GitWorktree]) -> GitWorktree? {
        guard let cwd = cwd.map(normalizePath), !cwd.isEmpty else { return nil }
        let containing = worktrees.filter {
            let p = normalizePath($0.path)
            return cwd == p || cwd.hasPrefix(p + "/")
        }
        guard let deepest = containing.max(by: { normalizePath($0.path).count < normalizePath($1.path).count })
        else { return nil }
        if let projectPath = projectPath.map(normalizePath), normalizePath(deepest.path) == projectPath { return nil }
        return deepest
    }
}
