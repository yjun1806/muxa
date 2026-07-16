import Foundation

/// 워크트리 폴더가 사라진 프로젝트 판정(순수) — **닫지 않고 배지로 표시**하기 위한 재료. 결정·근거는 ARCHITECTURE D31.
///
/// **보수적 선택**: 제거를 감지해도 파괴하지 않고 "제거됨"만 표시해 사용자가 직접 정리하게 한다 — 그 폴더 안에
/// **살아있는 cc·미저장 작업**이 있을 수 있어 자동으로 죽이면 안 된다(CLAUDE.md: 파괴는 좁게, 보존은 넓게).
///
/// 존재 확인은 부작용(FileManager)이라 **주입**받는다 — 판정 자체는 파일시스템을 안 건드리는 순수 함수라 테스트된다.
enum DeadWorktree {
    /// 실효 경로(`project.path ?? workspace.path`)가 **디스크에 없는** 프로젝트 id들.
    /// 경로가 아예 없는 프로젝트(경로 미상)는 대상이 아니다 — "사라졌다"고 말할 근거가 없다.
    static func projectIds(in workspaces: [Workspace], exists: (String) -> Bool) -> Set<String> {
        var result: Set<String> = []
        for workspace in workspaces {
            for project in workspace.projects {
                guard let path = project.path ?? workspace.path else { continue }
                if !exists(path) { result.insert(project.id) }
            }
        }
        return result
    }
}
