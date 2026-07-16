import Testing
@testable import muxa

/// 워크트리 폴더가 사라진 프로젝트 판정(순수) — **닫지 않고 배지로 표시**하기 위한 재료(D31).
/// 존재 확인은 주입(`exists`)이라 파일시스템 없이 결정론적으로 검증한다.
struct DeadWorktreeTests {
    private func workspace(path: String?, projects: [(id: String, path: String?)]) -> Workspace {
        Workspace(id: "ws", path: path, name: "ws",
                  projects: projects.map { Project(id: $0.id, name: $0.id, path: $0.path) },
                  activeProjectId: projects.first?.id ?? "")
    }

    @Test("실효 경로가 없는(디스크에서 사라진) 프로젝트만 고른다")
    func 사라진경로만() {
        let ws = workspace(path: "/repo", projects: [
            ("live", "/wt/live"), ("gone", "/wt/gone"),
        ])
        let present: Set<String> = ["/wt/live"]
        #expect(DeadWorktree.projectIds(in: [ws]) { present.contains($0) } == ["gone"])
    }

    @Test("경로를 상속하는 프로젝트는 워크스페이스 경로로 판정한다")
    func 상속경로판정() {
        let ws = workspace(path: "/wt/feature", projects: [("inherited", nil)])
        #expect(DeadWorktree.projectIds(in: [ws]) { _ in false } == ["inherited"])
    }

    @Test("경로가 아예 없으면 대상이 아니다 — 사라졌다고 말할 근거가 없다")
    func 경로없음제외() {
        let ws = workspace(path: nil, projects: [("nopath", nil)])
        #expect(DeadWorktree.projectIds(in: [ws]) { _ in false }.isEmpty)
    }

    @Test("모든 경로가 존재하면 비어 있다")
    func 전부존재() {
        let ws = workspace(path: "/repo", projects: [("main", nil), ("wt", "/wt/x")])
        #expect(DeadWorktree.projectIds(in: [ws]) { _ in true }.isEmpty)
    }

    @Test("여러 워크스페이스에 걸친 사라진 프로젝트를 모두 모은다")
    func 여러워크스페이스() {
        let a = workspace(path: "/a", projects: [("a-gone", "/a/wt")])
        let b = workspace(path: "/b-gone", projects: [("b-inherit", nil)])
        let present: Set<String> = []
        #expect(DeadWorktree.projectIds(in: [a, b]) { present.contains($0) } == ["a-gone", "b-inherit"])
    }
}
