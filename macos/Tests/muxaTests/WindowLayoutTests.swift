import Testing
@testable import muxa

/// 창 배치(순수) — 소유권 총함수(I1)·중복 불가(I2)·빈 창 없음(I5)·normalize 멱등(I8).
struct WindowLayoutTests {
    private let w1 = WindowID(rawValue: "w1")
    private let w2 = WindowID(rawValue: "w2")

    @Test func 저장분이_없으면_모든_프로젝트가_메인_소유다() {
        let windows = WindowLayout.normalize(nil, projectIds: ["p1", "p2"])
        #expect(windows.isEmpty)
        #expect(WindowLayout.owner(of: "p1", in: windows) == .main)
        #expect(WindowLayout.owner(of: "p2", in: windows) == .main)
    }

    @Test func 유령_프로젝트_id는_창에서_사라진다() {
        let saved = [ProjectWindow(id: w1, projectIds: ["p1", "gone"])]
        let windows = WindowLayout.normalize(saved, projectIds: ["p1"])
        #expect(windows.map(\.projectIds) == [["p1"]])
    }

    @Test func 같은_프로젝트가_두_창에_있으면_앞선_창이_이긴다() {
        let saved = [
            ProjectWindow(id: w1, projectIds: ["p1"]),
            ProjectWindow(id: w2, projectIds: ["p1", "p2"]),
        ]
        let windows = WindowLayout.normalize(saved, projectIds: ["p1", "p2"])
        #expect(WindowLayout.owner(of: "p1", in: windows) == w1)
        #expect(WindowLayout.owner(of: "p2", in: windows) == w2)
        #expect(windows.first(where: { $0.id == w2 })?.projectIds == ["p2"])
    }

    @Test func 어느_창에도_없는_프로젝트는_메인이_가진다() {
        let windows = [ProjectWindow(id: w1, projectIds: ["p1"])]
        #expect(WindowLayout.owner(of: "p9", in: windows) == .main)
    }

    @Test func move는_먼저_모든_창에서_제거한_뒤_대상에_넣는다() {
        let before = [
            ProjectWindow(id: w1, projectIds: ["p1", "p2"]),
            ProjectWindow(id: w2, projectIds: ["p3"]),
        ]
        let after = WindowLayout.move(["p1"], to: w2, in: before)
        #expect(after.first(where: { $0.id == w1 })?.projectIds == ["p2"])
        #expect(after.first(where: { $0.id == w2 })?.projectIds == ["p3", "p1"])
        // 결과가 disjoint여야 한다(I2) — 어떤 프로젝트도 두 창에 동시에 있을 수 없다.
        let all = after.flatMap(\.projectIds)
        #expect(all.count == Set(all).count)
    }

    @Test func move_to_main은_창에서_빼기만_한다() {
        let before = [ProjectWindow(id: w1, projectIds: ["p1", "p2"])]
        let after = WindowLayout.move(["p1"], to: .main, in: before)
        #expect(after.map(\.projectIds) == [["p2"]])
        #expect(WindowLayout.owner(of: "p1", in: after) == .main)
    }

    @Test func 마지막_프로젝트를_빼면_그_창은_사라진다() {
        let before = [ProjectWindow(id: w1, projectIds: ["p1"])]
        #expect(WindowLayout.move(["p1"], to: .main, in: before).isEmpty)
    }

    @Test func activeProjectId가_소유_밖이면_첫_항목으로_clamp된다() {
        let before = [ProjectWindow(id: w1, projectIds: ["p1", "p2"], activeProjectId: "p2")]
        let after = WindowLayout.move(["p2"], to: .main, in: before)
        #expect(after.first?.activeProjectId == "p1")

        let saved = [ProjectWindow(id: w1, projectIds: ["p1"], activeProjectId: "gone")]
        #expect(WindowLayout.normalize(saved, projectIds: ["p1"]).first?.activeProjectId == "p1")
    }

    @Test func normalize는_멱등이다() {
        let saved = [
            ProjectWindow(id: w1, projectIds: ["p1", "p1", "gone"], activeProjectId: "gone"),
            ProjectWindow(id: w1, projectIds: ["p2"]),
            ProjectWindow(id: w2, projectIds: ["p1", "p2"]),
            ProjectWindow(id: .main, projectIds: ["p3"]),
            ProjectWindow(id: WindowID(rawValue: "empty"), projectIds: []),
        ]
        let once = WindowLayout.normalize(saved, projectIds: ["p1", "p2", "p3"])
        let twice = WindowLayout.normalize(once, projectIds: ["p1", "p2", "p3"])
        #expect(once == twice)
        // 메인은 여집합이므로 목록에 남지 않는다 — p3는 그래도 유실되지 않는다.
        #expect(WindowLayout.owner(of: "p3", in: once) == .main)
    }

    @Test func 중복_창_id는_앞선_것만_남는다() {
        let saved = [
            ProjectWindow(id: w1, projectIds: ["p1"]),
            ProjectWindow(id: w1, projectIds: ["p2"]),
        ]
        let windows = WindowLayout.normalize(saved, projectIds: ["p1", "p2"])
        #expect(windows.count == 1)
        #expect(windows.first?.projectIds == ["p1"])
        #expect(WindowLayout.owner(of: "p2", in: windows) == .main)
    }

    @Test func 워크스페이스_분리는_move의_설탕이다() {
        // 워크스페이스 단위 분리 = 그 워크스페이스의 전 프로젝트를 한 창으로 move.
        let seeded = [ProjectWindow(id: w1, projectIds: ["p1"], activeProjectId: "p1")]
        let after = WindowLayout.move(["p1", "p2", "p3"], to: w1, in: seeded)
        #expect(after.map(\.projectIds) == [["p1", "p2", "p3"]])
        #expect(after.first?.activeProjectId == "p1")
    }

    // MARK: 보이는 활성 프로젝트 (배지 판정의 입력)

    @Test func 분리_창의_활성_프로젝트도_보이는_것으로_친다() {
        let windows = [ProjectWindow(id: w1, projectIds: ["p2", "p3"], activeProjectId: "p2")]
        let visible = WindowLayout.visibleActiveProjects(mainActive: "p1", in: windows)
        #expect(visible == ["p1", "p2"])   // p3는 그 창의 비활성 프로젝트라 안 보인다
    }

    @Test func 메인의_활성_프로젝트가_분리돼_있으면_보이지_않는다() {
        // 메인의 활성 프로젝트(p1)가 분리 창으로 갔고 그 창은 p4를 보고 있다 —
        // 메인은 p1 자리에 플레이스홀더를 그리므로 p1은 아무 데서도 안 보인다(배지가 붙어야 한다).
        let windows = [ProjectWindow(id: w1, projectIds: ["p1", "p4"], activeProjectId: "p4")]
        #expect(WindowLayout.visibleActiveProjects(mainActive: "p1", in: windows) == ["p4"])
    }

    // MARK: 메인 창의 프로젝트 순환

    @Test func 순환_전환은_분리된_프로젝트를_건너뛴다() {
        let windows = [ProjectWindow(id: w1, projectIds: ["p2"], activeProjectId: "p2")]
        let ids = ["p1", "p2", "p3"]
        #expect(WindowLayout.nextMainProject(from: "p1", in: ids, forward: true, windows: windows) == "p3")
        #expect(WindowLayout.nextMainProject(from: "p3", in: ids, forward: false, windows: windows) == "p1")
    }

    @Test func 메인에_돌_프로젝트가_없으면_순환하지_않는다() {
        let windows = [ProjectWindow(id: w1, projectIds: ["p2", "p3"], activeProjectId: "p2")]
        #expect(WindowLayout.nextMainProject(from: "p1", in: ["p1", "p2", "p3"],
                                             forward: true, windows: windows) == nil)
        #expect(WindowLayout.nextMainProject(from: "p1", in: ["p1"],
                                             forward: true, windows: []) == nil)
    }
}
