import CoreGraphics // 커서 위치 판정(dropTarget)이 CGFloat을 쓴다
import Testing
@testable import muxa

/// 사이드바 2단 트리의 순수 판정 — 펼침 규칙·상태 우선순위·주의 큐 대상.
/// UI 없이 검증된다(뷰가 규칙을 재구현하면 여기서 안 잡히므로, 뷰는 반드시 이 함수를 부른다).
struct SidebarTreeTests {
    // MARK: 펼침

    @Test func 집합에_있으면_펼쳐진다() {
        #expect(SidebarTree.isExpanded(wsId: "b", expanded: ["b"]))
        #expect(!SidebarTree.isExpanded(wsId: "b", expanded: []))
    }

    @Test func 토글은_그_하나만_넣고_뺀다() {
        // 활성이든 아니든 특례 없이 순수 토글 — 다른 워크스페이스는 건드리지 않는다(아코디언 아님).
        let opened = SidebarTree.toggled(["c"], wsId: "b")
        #expect(opened == ["b", "c"]) // 기존 펼침(c)은 그대로
        #expect(SidebarTree.toggled(opened, wsId: "b") == ["c"])
    }

    @Test func 저장값이_없으면_활성만_펼친다() {
        #expect(SidebarTree.restore(saved: nil, activeId: "a", workspaceIds: ["a", "b"]) == ["a"])
    }

    @Test func 활성은_저장분에_없어도_펼친_채_복원된다() {
        // 구 저장분 마이그레이션 — 활성 a는 집합에 없지만 로드 시 보태진다.
        #expect(SidebarTree.restore(saved: ["b"], activeId: "a", workspaceIds: ["a", "b"]) == ["a", "b"])
    }

    @Test func 사라진_워크스페이스_id는_복원에서_버린다() {
        #expect(SidebarTree.restore(saved: ["a", "zombie"], activeId: "a", workspaceIds: ["a"]) == ["a"])
    }

    @Test func prune은_존재하는_id만_남긴다() {
        #expect(SidebarTree.prune(["a", "x"], workspaceIds: ["a", "b"]) == ["a"])
    }

    // MARK: 순서 (드래그 앤 드롭 재정렬)

    @Test func 뒤로_옮기면_대상_다음에_들어간다() {
        // a를 c 뒤로 — remove 후 target을 다시 찾아 off-by-one을 막는다.
        #expect(SidebarTree.reordered(["a", "b", "c", "d"], move: "a",
                                      adjacentTo: "c", placeBefore: false) == ["b", "c", "a", "d"])
    }

    @Test func 바로_다음_이웃_뒤로_옮기는_off_by_one() {
        // a를 바로 뒤 이웃 b의 뒤로 — 앞→뒤 이동에서 인덱스가 당겨지는 고전적 함정.
        #expect(SidebarTree.reordered(["a", "b", "c"], move: "a",
                                      adjacentTo: "b", placeBefore: false) == ["b", "a", "c"])
    }

    @Test func 앞으로_옮기면_대상_바로_앞에_들어간다() {
        #expect(SidebarTree.reordered(["a", "b", "c", "d"], move: "d",
                                      adjacentTo: "b", placeBefore: true) == ["a", "d", "b", "c"])
    }

    @Test func 맨_뒤와_맨_앞으로_옮길_수_있다() {
        #expect(SidebarTree.reordered(["a", "b", "c", "d"], move: "b",
                                      adjacentTo: "d", placeBefore: false) == ["a", "c", "d", "b"])
        #expect(SidebarTree.reordered(["a", "b", "c", "d"], move: "c",
                                      adjacentTo: "a", placeBefore: true) == ["c", "a", "b", "d"])
    }

    @Test func 자기_자신_위로는_원본_그대로다() {
        #expect(SidebarTree.reordered(["a", "b", "c"], move: "b",
                                      adjacentTo: "b", placeBefore: true) == ["a", "b", "c"])
    }

    @Test func 미존재_id는_no_op이다() {
        #expect(SidebarTree.reordered(["a", "b"], move: "x",
                                      adjacentTo: "a", placeBefore: true) == ["a", "b"])
        #expect(SidebarTree.reordered(["a", "b"], move: "a",
                                      adjacentTo: "zzz", placeBefore: false) == ["a", "b"])
    }

    // MARK: 커서 위치 → 삽입 자리 (그립 드래그)

    /// 행 높이 24, 간격 4 기준의 세 행 — 중심은 12 / 40 / 68.
    private static let mids: [(id: String, midY: CGFloat)] = [("a", 12), ("b", 40), ("c", 68)]

    @Test func 행_중심보다_위면_그_행_앞이다() {
        let hit = SidebarTree.dropTarget(y: 34, rowMids: Self.mids, dragged: "a")
        #expect(hit?.targetId == "b")
        #expect(hit?.placeBefore == true)
    }

    @Test func 행_중심보다_아래면_그_행_뒤다() {
        let hit = SidebarTree.dropTarget(y: 46, rowMids: Self.mids, dragged: "a")
        #expect(hit?.targetId == "b")
        #expect(hit?.placeBefore == false)
    }

    @Test func 행_사이_틈도_가장_가까운_행으로_흡수된다() {
        // 26 = b의 윗변 근처(틈) — 중심 12(a)보다 40(b)에 가깝다.
        #expect(SidebarTree.dropTarget(y: 27, rowMids: Self.mids, dragged: "a")?.targetId == "b")
    }

    @Test func 목록_위아래로_벗어나도_양끝_행을_가리킨다() {
        let above = SidebarTree.dropTarget(y: -500, rowMids: Self.mids, dragged: "c")
        #expect(above?.targetId == "a")
        #expect(above?.placeBefore == true)
        let below = SidebarTree.dropTarget(y: 900, rowMids: Self.mids, dragged: "a")
        #expect(below?.targetId == "c")
        #expect(below?.placeBefore == false)
    }

    @Test func 자기_자신을_가리키면_이동_없음이다() {
        #expect(SidebarTree.dropTarget(y: 12, rowMids: Self.mids, dragged: "a") == nil)
    }

    @Test func 행이_하나도_없으면_이동_없음이다() {
        #expect(SidebarTree.dropTarget(y: 10, rowMids: [], dragged: "a") == nil)
    }

    /// 호출부가 딕셔너리에서 만든 배열을 넘겨 순회 순서가 실행마다 다르다 — 거리가 같을 때
    /// 답이 흔들리면 안 된다(같은 손놀림에 다른 결과가 나온다).
    @Test func 거리가_같으면_순회_순서와_무관하게_같은_답이다() {
        let ab: [(id: String, midY: CGFloat)] = [("a", 12), ("b", 40)]
        let ba: [(id: String, midY: CGFloat)] = [("b", 40), ("a", 12)]
        let mid: CGFloat = 26 // a와 b의 정확한 중간
        #expect(SidebarTree.dropTarget(y: mid, rowMids: ab, dragged: "z")?.targetId
                == SidebarTree.dropTarget(y: mid, rowMids: ba, dragged: "z")?.targetId)
    }

    // MARK: 순서 적용 (미리보기와 저장이 공유하는 방어선)

    @Test func 순서대로_워크스페이스를_재배열한다() {
        let next = SidebarTree.applyOrder(["w1", "w0"], to: fixture())
        #expect(next?.map(\.id) == ["w1", "w0"])
    }

    @Test func 개수가_줄면_nil이다() {
        // compactMap이 조용히 하나를 떨구면 워크스페이스가 사라진다 — 결과를 쓰면 안 된다.
        #expect(SidebarTree.applyOrder(["w0"], to: fixture()) == nil)
        #expect(SidebarTree.applyOrder(["w0", "없는id"], to: fixture()) == nil)
    }

    /// 화면(미리보기)과 저장이 **같은 순서**여야 한다 — 어긋나면 놓는 순간 목록이 튄다.
    @Test func 미리보기와_확정_순서는_같은_규칙에서_나온다() {
        let workspaces = fixture()
        let order = SidebarTree.reordered(workspaces.map(\.id), move: "w1",
                                          adjacentTo: "w0", placeBefore: true)
        #expect(SidebarTree.applyOrder(order, to: workspaces)?.map(\.id) == order)
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
        #expect(ref == SidebarTree.WaitingRef(workspaceId: "w0", workspaceName: "one",
                                              projectId: "p0b", projectName: "beta"))
    }

    @Test func 대기_큐는_배지_전부를_선언_순서로_나열한다() {
        // ⌘⇧A 순회 순서(waitingSlots)와 같은 순서여야 카드의 행과 점프가 어긋나지 않는다.
        let refs = SidebarTree.allWaiting(workspaces: fixture(), badged: ["p1a", "p0a", "p0b"])
        #expect(refs.map(\.projectId) == ["p0a", "p0b", "p1a"])
        // 카드 행이 "어느 워크스페이스의 프로젝트인가"를 말할 수 있어야 한다 — 이름이 실려 온다.
        #expect(refs.map(\.workspaceName) == ["one", "one", "two"])
    }

    @Test func 배지가_없으면_큐_카드는_없다() {
        #expect(SidebarTree.firstWaiting(workspaces: fixture(), badged: []) == nil)
        #expect(SidebarTree.allWaiting(workspaces: fixture(), badged: []).isEmpty)
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
