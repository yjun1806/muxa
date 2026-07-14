import Testing
@testable import muxa

/// 사이드바 2단 트리의 순수 판정 — 펼침 규칙·상태 우선순위·주의 큐 대상.
/// UI 없이 검증된다(뷰가 규칙을 재구현하면 여기서 안 잡히므로, 뷰는 반드시 이 함수를 부른다).
struct SidebarTreeTests {
    // MARK: 펼침

    @Test func 활성_워크스페이스는_집합에_없어도_펼쳐진다() {
        #expect(SidebarTree.isExpanded(wsId: "a", activeId: "a", expanded: []))
    }

    @Test func 비활성은_집합에_있을_때만_펼쳐진다() {
        #expect(SidebarTree.isExpanded(wsId: "b", activeId: "a", expanded: ["b"]))
        #expect(!SidebarTree.isExpanded(wsId: "b", activeId: "a", expanded: []))
    }

    @Test func 활성_워크스페이스는_접히지_않는다() {
        // 디스클로저를 눌러도 집합이 그대로 — 거짓 어포던스를 만들지 않기 위해 뷰에선 비활성으로 둔다.
        #expect(SidebarTree.toggled([], wsId: "a", activeId: "a") == [])
        #expect(SidebarTree.toggled(["b"], wsId: "a", activeId: "a") == ["b"])
    }

    @Test func 비활성_토글은_넣고_빼기를_반복한다() {
        let opened = SidebarTree.toggled([], wsId: "b", activeId: "a")
        #expect(opened == ["b"])
        #expect(SidebarTree.toggled(opened, wsId: "b", activeId: "a") == [])
    }

    @Test func 저장값이_없으면_활성만_펼친다() {
        #expect(SidebarTree.restore(saved: nil, workspaceIds: ["a", "b"]) == [])
    }

    @Test func 사라진_워크스페이스_id는_복원에서_버린다() {
        #expect(SidebarTree.restore(saved: ["a", "zombie"], workspaceIds: ["a"]) == ["a"])
    }

    @Test func prune은_존재하는_id만_남긴다() {
        #expect(SidebarTree.prune(["a", "x"], workspaceIds: ["a", "b"]) == ["a"])
    }

    // MARK: 상태 신호

    @Test func 주의는_작업중을_이긴다() {
        #expect(SidebarTree.status(.init(isBadged: true, isWorking: true)) == .attention)
        #expect(SidebarTree.status(.init(isWaiting: true, isWorking: true)) == .attention)
    }

    @Test func 배지만_있어도_대기만_있어도_죽은_서비스만_있어도_주의다() {
        #expect(SidebarTree.status(.init(isBadged: true)) == .attention)
        #expect(SidebarTree.status(.init(isWaiting: true)) == .attention)
        #expect(SidebarTree.status(.init(hasDeadService: true)) == .attention)
    }

    @Test func 작업중만_있으면_작업중이고_신호가_없으면_유휴다() {
        #expect(SidebarTree.status(.init(isWorking: true)) == .working)
        #expect(SidebarTree.status(.init()) == .idle)
    }

    @Test func 롤업은_가장_센_신호를_고른다() {
        #expect(SidebarTree.rollup([.idle, .working, .attention]) == .attention)
        #expect(SidebarTree.rollup([.idle, .working]) == .working)
        #expect(SidebarTree.rollup([.idle, .idle]) == .idle)
        #expect(SidebarTree.rollup([]) == .idle) // 프로젝트가 없으면 조용하다
    }

    // MARK: 주의 큐

    @Test func 첫_대기_프로젝트는_워크스페이스_프로젝트_순서로_고른다() {
        let ws = fixture()
        // ws0의 두 번째 프로젝트와 ws1의 첫 프로젝트가 모두 배지 → 앞선 워크스페이스가 이긴다.
        let ref = SidebarTree.firstWaiting(workspaces: ws, badged: ["p0b", "p1a"])
        #expect(ref == SidebarTree.WaitingRef(workspaceId: "w0", projectId: "p0b", projectName: "beta"))
    }

    @Test func 배지가_없으면_큐_헤더는_없다() {
        #expect(SidebarTree.firstWaiting(workspaces: fixture(), badged: []) == nil)
    }

    private func fixture() -> [Workspace] {
        [
            Workspace(id: "w0", path: nil, name: "one",
                      projects: [Project(id: "p0a", name: "alpha", path: nil),
                                 Project(id: "p0b", name: "beta", path: nil)],
                      activeProjectId: "p0a"),
            Workspace(id: "w1", path: nil, name: "two",
                      projects: [Project(id: "p1a", name: "gamma", path: nil)],
                      activeProjectId: "p1a"),
        ]
    }
}
