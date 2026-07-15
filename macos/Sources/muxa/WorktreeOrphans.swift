import Foundation

/// 워크트리 디렉터리가 사라졌을 때 **고아가 되는 프로젝트** 판정(순수).
///
/// `git worktree remove`·'병합 후 정리'는 디스크에서 워크트리 폴더를 통째로 지운다. 그 폴더를 cwd로
/// 쓰던 프로젝트는 죽은 경로만 남는다 — 새 탭은 없는 폴더에서 열리고, git 패널은 "저장소 아님",
/// dev 서버 tmux 세션은 좀비로 포트를 문 채 남는다. 판정은 값으로, 실제 닫기(서비스·세션 종료)는
/// 경계(AppState.closeProjects)에서. (CLAUDE.md: 파괴는 좁게, 보존은 넓게)
enum WorktreeOrphans {
    /// 제거된 경로(그 하위 포함)를 실효 cwd로 쓰는 프로젝트 id들.
    /// 실효 cwd = 프로젝트 경로, 없으면 상속하는 워크스페이스 경로. 경로가 아예 없으면 대상이 아니다.
    ///
    /// **경로를 상속만 하는 프로젝트도 대상이다.** 워크스페이스 경로 자체가 지워진 워크트리라면 그걸
    /// 상속하는 프로젝트의 cwd도 실제로 사라진 것이라, 안 닫으면 없는 폴더에 tmux 세션이 포트를 문 채
    /// 좀비로 남는다 — 이 판정이 존재하는 이유가 정확히 그거다. (판정은 여기, 실제 종료는 경계에서.)
    static func projectIds(in workspaces: [Workspace], removedPath: String) -> [String] {
        let root = normalizePath(removedPath)
        guard !root.isEmpty, root != "/" else { return [] } // 루트는 절대 대상이 아니다(전부 닫힌다)
        return workspaces.flatMap { workspace in
            workspace.projects.compactMap { project -> String? in
                guard let path = (project.path ?? workspace.path).map(normalizePath) else { return nil }
                guard path == root || path.hasPrefix(root + "/") else { return nil }
                return project.id
            }
        }
    }
}
