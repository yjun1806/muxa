import Foundation
import Testing
@testable import muxa

/// 사이드바 펼침 상태의 영속 왕복 — CodingKeys 누락(인코딩은 되는데 저장이 안 되는 버그) 회귀 방지.
@MainActor
struct PersistedSidebarTests {
    private func snapshot(expanded: [String]? = nil, windows: [ProjectWindow]? = nil) -> AppState.Persisted {
        AppState.Persisted(workspaces: [], activeId: "a", sidebarMode: .expanded, layouts: nil,
                           explorerWidth: nil, gitPanelWidth: nil, serviceDockWidth: nil,
                           showExplorer: nil, showGitPanel: nil,
                           expandedWorkspaces: expanded, windows: windows)
    }

    @Test func 펼침_집합이_저장되고_그대로_돌아온다() throws {
        let data = try JSONEncoder().encode(snapshot(expanded: ["a", "b"]))
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: data)
        #expect(back.expandedWorkspaces == ["a", "b"])
    }

    @Test func 구_스냅샷은_펼침_필드가_없어도_디코드된다() throws {
        // version 필드도 없던 pre-version 저장분 — 하위호환의 최저선.
        let json = Data(#"{"workspaces":[],"activeId":"a","sidebarMode":"expanded"}"#.utf8)
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: json)
        #expect(back.expandedWorkspaces == nil)
        #expect(back.version == 0)
    }

    @Test func 분리_창_목록이_저장되고_그대로_돌아온다() throws {
        let window = ProjectWindow(id: WindowID(rawValue: "w1"), projectIds: ["p1", "p2"],
                                   activeProjectId: "p2",
                                   frame: FrameSnapshot(x: 10, y: 20, width: 900, height: 600),
                                   showExplorer: true, explorerWidth: 300)
        let data = try JSONEncoder().encode(snapshot(windows: [window]))
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: data)
        #expect(back.windows == [window])
    }

    @Test func 구_저장분은_windows가_nil로_디코드된다() throws {
        let json = Data(#"{"workspaces":[],"activeId":"a","sidebarMode":"expanded"}"#.utf8)
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: json)
        #expect(back.windows == nil)
        #expect(back.version == 0)
    }

    @Test func 펼침은_정렬된_순서로_저장된다() throws {
        // save()가 Set.sorted()를 넘긴다는 계약 — 인코딩 결과가 매 저장마다 뒤바뀌지 않는다.
        let sorted = Set(["b", "a", "c"]).sorted()
        let data = try JSONEncoder().encode(snapshot(expanded: sorted))
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: data)
        #expect(back.expandedWorkspaces == ["a", "b", "c"])
    }
}
