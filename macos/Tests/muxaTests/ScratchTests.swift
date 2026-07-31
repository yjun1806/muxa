import Foundation
import Testing
@testable import muxa

/// Scratch 순수 판정·상수·마이그레이션 검증 — UI 없이 못 박는다.
/// (스크래치는 이제 workspace/projectWindows 밖의 독립 창+store다 — 그 결합점을 없애는 게 이 pivot의 목적.)
struct ScratchTests {
    /// 구 저장분이 workspaces[0]에 넣어 두던 스크래치 워크스페이스(마이그레이션 입력용).
    private func legacyScratch() -> Workspace {
        Workspace(id: Scratch.workspaceId, path: "/h", name: Scratch.label,
                  projects: [Project(id: Scratch.projectId, name: Scratch.label, path: nil)],
                  activeProjectId: Scratch.projectId)
    }

    // MARK: 상수 안정성 — 재시작 생존의 근거(랜덤 id면 layout/tmux 유실)

    @Test func windowIdIsStableConstant() {
        #expect(Scratch.windowId.rawValue == "muxa.scratch.window")
        #expect(!Scratch.windowId.isMain) // 메인이 아니라 독립 창(별도 창 전용)
    }

    @Test func projectAndLabelConstants() {
        #expect(Scratch.projectId == "muxa.scratch.home") // layout·tmux 키 — 절대 바뀌면 안 된다
        #expect(Scratch.label == "~")
        #expect(Scratch.workspaceId == "muxa.scratch") // 마이그레이션 전용으로 남는다
    }

    // MARK: 레거시 마이그레이션 — 구 저장분의 스크래치 워크스페이스 스트립

    @Test func stripLegacyRemovesScratchWorkspace() {
        let a = createWorkspace(path: "/a", name: "A")
        let result = Scratch.stripLegacyWorkspace([legacyScratch(), a], activeId: a.id)
        #expect(result.workspaces.map(\.id) == [a.id]) // 스크래치 제거
        #expect(result.activeId == a.id) // 활성은 그대로
    }

    @Test func stripLegacyFallsBackWhenScratchWasActive() {
        let a = createWorkspace(path: "/a", name: "A")
        let b = createWorkspace(path: "/b", name: "B")
        // activeId가 스크래치였으면 첫 실 워크스페이스로 폴백(빈 화면 방지).
        let result = Scratch.stripLegacyWorkspace([legacyScratch(), a, b], activeId: Scratch.workspaceId)
        #expect(result.workspaces.map(\.id) == [a.id, b.id])
        #expect(result.activeId == a.id)
    }

    @Test func stripLegacyIsIdempotentWhenNoScratch() {
        let a = createWorkspace(path: "/a", name: "A")
        let b = createWorkspace(path: "/b", name: "B")
        let once = Scratch.stripLegacyWorkspace([a, b], activeId: b.id)
        #expect(once.workspaces.map(\.id) == [a.id, b.id]) // 불변
        #expect(once.activeId == b.id)
        let twice = Scratch.stripLegacyWorkspace(once.workspaces, activeId: once.activeId)
        #expect(twice.workspaces.map(\.id) == once.workspaces.map(\.id)) // 멱등
    }

    @Test func stripLegacyEmptyResultClearsActive() {
        // 스크래치만 있던(=실 워크스페이스 0) 극단 케이스 — 폴백할 곳이 없으면 활성은 빈 문자열.
        let result = Scratch.stripLegacyWorkspace([legacyScratch()], activeId: Scratch.workspaceId)
        #expect(result.workspaces.isEmpty)
        #expect(result.activeId == "")
    }

    // MARK: Persisted 왕복 — 스크래치는 workspaces 밖(일회용이라 창 상태·레이아웃을 지속하지 않는다)

    @MainActor
    @Test func persistedRoundTripKeepsScratchOutOfWorkspaces() throws {
        let a = createWorkspace(path: "/a", name: "A")
        let snapshot = AppState.Persisted(
            workspaces: [a], activeId: a.id, sidebarMode: .expanded,
            layouts: nil, explorerWidth: nil, gitPanelWidth: nil, serviceDockWidth: nil,
            showExplorer: nil, showGitPanel: nil, expandedWorkspaces: nil)
        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(AppState.Persisted.self, from: data)
        #expect(!(back.workspaces.contains { Scratch.isScratchWorkspace($0.id) })) // 스크래치는 workspaces 밖
    }
}
