import Testing
@testable import muxa

/// 워크트리 폴더가 지워졌을 때 고아가 되는 프로젝트 판정(순수) — 파괴는 좁게, 보존은 넓게.
struct WorktreeOrphansTests {
    /// 워크스페이스 하나 + 프로젝트들(경로는 nil이면 워크스페이스 상속).
    private func workspace(path: String?, projects: [(id: String, path: String?)]) -> Workspace {
        Workspace(id: "ws", path: path, name: "ws",
                  projects: projects.map { Project(id: $0.id, name: $0.id, path: $0.path) },
                  activeProjectId: projects.first?.id ?? "")
    }

    @Test("제거된 워크트리 경로를 쓰는 프로젝트만 고른다")
    func 정확한경로만() {
        let ws = workspace(path: "/repo", projects: [
            ("main", nil), ("wt", "/repo/../wt-x"), ("feature", "/wt/feature"), ("other", "/wt/other"),
        ])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature") == ["feature"])
    }

    @Test("제거된 폴더의 하위 경로 프로젝트도 고아다")
    func 하위경로포함() {
        let ws = workspace(path: "/repo", projects: [("sub", "/wt/feature/apps/web")])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature") == ["sub"])
    }

    @Test("이름만 겹치는 형제 폴더는 고아가 아니다")
    func 접두사오판방지() {
        let ws = workspace(path: "/repo", projects: [("sibling", "/wt/feature-2")])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature").isEmpty)
    }

    @Test("뒤 슬래시가 있어도 같은 경로로 본다")
    func 뒤슬래시정규화() {
        let ws = workspace(path: "/repo", projects: [("feature", "/wt/feature/")])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature") == ["feature"])
    }

    @Test("경로를 상속하는 프로젝트는 워크스페이스 경로로 판정한다")
    func 상속경로판정() {
        let ws = workspace(path: "/wt/feature", projects: [("inherited", nil)])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature") == ["inherited"])
    }

    @Test("경로가 아예 없으면 대상이 아니다")
    func 경로없음제외() {
        let ws = workspace(path: nil, projects: [("nopath", nil)])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/wt/feature").isEmpty)
    }

    @Test("루트(/)는 절대 고아 판정 대상이 아니다")
    func 루트는제외() {
        let ws = workspace(path: "/", projects: [("a", "/repo"), ("b", nil)])
        #expect(WorktreeOrphans.projectIds(in: [ws], removedPath: "/").isEmpty)
    }
}
