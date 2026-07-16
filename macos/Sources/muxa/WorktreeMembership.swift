import Bonsplit
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

/// 워크트리에서 도는 작업이 살아 있는 **다른 프로젝트의 탭** — 링크 카드가 지목한다(D31). 판정은 `AppState.externalLiveSession`.
struct ExternalWorktreeSession {
    let originProjectId: String
    /// 원본 프로젝트의 표시 이름 — 링크 탭이 "어디의 탭인지"를 지목한다(무명 "다른 탭"은 [가서 보기]의 목적지를 숨긴다).
    let originName: String
    let tabId: TabID
    /// 영속(∞ tmux) 탭인가 — 그렇다면 "가져오기"(이식)가 가능하다. 일반 터미널은 "가서 보기"만.
    let isPersistent: Bool
}

/// 진행 중인 세션(∞ 탭)이 **다른 프로젝트(워크트리)** 안에서 작업 중일 때의 이동 대상 — 원본 칸 상단
/// "옮길까요?" 배너(D31 이동 배지)가 그린다. 판정은 `AppState.worktreeMoveSuggestion`.
struct WorktreeMoveSuggestion: Equatable {
    let targetProjectId: String
    let targetName: String
}

/// 워크트리 프로젝트에서 도는 작업이 **다른 프로젝트의 탭**에 살아 있는지 판정(순수) — 링크 카드(D31)의 재료.
///
/// 에이전트가 옛 탭 안에서 `git worktree add` 후 그 안으로 `cd`하면, 새 워크트리가 프로젝트로 승격돼도
/// 살아있는 세션은 옛 프로젝트 탭에 갇힌다. 그 탭의 cwd(OSC 7)가 이 워크트리 경로 안이면 링크 카드로 이어준다
/// ("가서 보기"/영속탭이면 "가져오기"). cwd 스캔·이식은 경계(AppState·TerminalStore), 매칭만 여기서 순수하게.
enum WorktreeLink {
    /// 이 cwd를 담는 프로젝트 중 **경로가 가장 긴(가장 구체적인)** 프로젝트의 인덱스 = 그 세션의 "임자". 없으면 nil.
    /// 워크트리는 보통 레포 루트 하위(`<repo>/.worktrees/<b>`)에 살아, **루트 프로젝트가 하위 워크트리 세션을
    /// 가로채는 것**을 막는다 — 링크 카드는 임자 프로젝트에만 뜨게 한다. 루트(`/`)·빈 경로는 임자가 될 수 없다.
    static func owner(pwd: String, projectPaths: [String]) -> Int? {
        let target = normalizePath(pwd)
        guard !target.isEmpty else { return nil }
        var best: Int?
        var bestLen = -1
        for (i, raw) in projectPaths.enumerated() {
            let p = normalizePath(raw)
            guard !p.isEmpty, p != "/", target == p || target.hasPrefix(p + "/") else { continue }
            if p.count > bestLen { bestLen = p.count; best = i }
        }
        return best
    }
}
