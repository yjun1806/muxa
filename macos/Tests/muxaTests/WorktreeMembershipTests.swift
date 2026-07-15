import Testing
@testable import muxa

/// 워크트리 ↔ 프로젝트 소속 판정(순수) — 감지·승격(D31 1단계)과 이동 배지(2단계)의 코어.
struct WorktreeMembershipTests {
    private func ws(path: String?, projects: [(id: String, path: String?)], ack: [String]? = nil) -> Workspace {
        Workspace(id: "ws", path: path, name: "ws",
                  projects: projects.map { Project(id: $0.id, name: $0.id, path: $0.path) },
                  activeProjectId: projects.first?.id ?? "",
                  acknowledgedWorktreePaths: ack)
    }

    private func wt(_ path: String, branch: String? = nil, bare: Bool = false,
                    detached: Bool = false, main: Bool = false) -> GitWorktree {
        GitWorktree(path: path, branch: branch, head: "deadbeef", isBare: bare, isDetached: detached, isMain: main)
    }

    // MARK: - WorktreePromotion.pending

    @Test("메인 워크트리(워크스페이스 경로 상속)는 승격되지 않는다")
    func 메인은승격안됨() {
        let workspace = ws(path: "/repo", projects: [("main", nil)])
        let trees = [wt("/repo", branch: "main")]
        #expect(WorktreePromotion.pending(worktrees: trees, in: workspace).isEmpty)
    }

    @Test("사이드바에 없는 워크트리만 승격 후보로 고른다")
    func 새워크트리만후보() {
        let workspace = ws(path: "/repo", projects: [("main", nil), ("feat", "/repo/.worktrees/feat")])
        let trees = [
            wt("/repo", branch: "main"),                       // 메인 = 상속으로 덮임
            wt("/repo/.worktrees/feat", branch: "feat"),       // 이미 프로젝트
            wt("/repo/.worktrees/fix", branch: "fix"),         // 신규 → 후보
        ]
        let pending = WorktreePromotion.pending(worktrees: trees, in: workspace)
        #expect(pending.map(\.path) == ["/repo/.worktrees/fix"])
    }

    @Test("bare 워크트리는 후보가 아니다(체크아웃 없음)")
    func bare제외() {
        let workspace = ws(path: "/repo", projects: [("main", nil)])
        let trees = [wt("/bare.git", bare: true), wt("/repo/wt-x", branch: "x")]
        #expect(WorktreePromotion.pending(worktrees: trees, in: workspace).map(\.path) == ["/repo/wt-x"])
    }

    @Test("뒤 슬래시가 달라도 같은 경로로 본다")
    func 정규화() {
        let workspace = ws(path: "/repo", projects: [("main", nil), ("feat", "/repo/wt/feat/")])
        let trees = [wt("/repo/wt/feat", branch: "feat")]
        #expect(WorktreePromotion.pending(worktrees: trees, in: workspace).isEmpty)
    }

    @Test("agent가 규약 밖 경로에 만든 워크트리도 후보다")
    func 규약밖경로() {
        let workspace = ws(path: "/repo", projects: [("main", nil)])
        let trees = [wt("/tmp/adhoc-wt", branch: "spike")]
        #expect(WorktreePromotion.pending(worktrees: trees, in: workspace).map(\.path) == ["/tmp/adhoc-wt"])
    }

    @Test("path 없는 워크스페이스에서도 메인 워킹트리(isMain)는 제안하지 않는다")
    func nil워크스페이스경로_메인제외() {
        // 초기 워크스페이스는 프로세스 cwd라 path가 nil일 수 있다 — covered가 비어도 isMain으로 걸러야 한다.
        let workspace = ws(path: nil, projects: [("main", nil)])
        let trees = [wt("/repo", branch: "main", main: true), wt("/repo/wt-x", branch: "x")]
        #expect(WorktreePromotion.pending(worktrees: trees, in: workspace).map(\.path) == ["/repo/wt-x"])
        #expect(WorktreePromotion.offers(worktrees: trees, in: workspace).map(\.path) == ["/repo/wt-x"])
    }

    // MARK: - WorktreePromotion.offers (pending − baseline)

    @Test("baseline(이미 처리)에 있는 워크트리는 제안하지 않는다")
    func baseline제외() {
        let workspace = ws(path: "/repo", projects: [("main", nil)],
                           ack: ["/repo/.worktrees/dismissed"])
        let trees = [
            wt("/repo/.worktrees/dismissed", branch: "old"),  // 이미 무시함 → 제안 안 함
            wt("/repo/.worktrees/fresh", branch: "new"),      // 신규 → 제안
        ]
        #expect(WorktreePromotion.offers(worktrees: trees, in: workspace).map(\.path)
                == ["/repo/.worktrees/fresh"])
    }

    @Test("baseline이 비면 pending과 같다")
    func baseline없으면pending과동일() {
        let workspace = ws(path: "/repo", projects: [("main", nil)])
        let trees = [wt("/repo", branch: "main"), wt("/repo/wt-x", branch: "x")]
        let offers = WorktreePromotion.offers(worktrees: trees, in: workspace)
        let pending = WorktreePromotion.pending(worktrees: trees, in: workspace)
        #expect(offers.map(\.path) == pending.map(\.path))
        #expect(offers.map(\.path) == ["/repo/wt-x"])
    }

    // MARK: - WorktreeMove.target

    @Test("cwd가 소속과 다른 워크트리에 있으면 그 워크트리를 이동 대상으로 준다")
    func 다른워크트리로이동() {
        let trees = [wt("/repo", branch: "main"), wt("/repo/.worktrees/feat", branch: "feat")]
        let target = WorktreeMove.target(cwd: "/repo/.worktrees/feat", projectPath: "/repo", worktrees: trees)
        #expect(target?.path == "/repo/.worktrees/feat")
    }

    @Test("cwd가 이미 소속 경로면 이동하지 않는다")
    func 이미소속이면없음() {
        let trees = [wt("/repo", branch: "main"), wt("/repo/.worktrees/feat", branch: "feat")]
        #expect(WorktreeMove.target(cwd: "/repo/.worktrees/feat", projectPath: "/repo/.worktrees/feat", worktrees: trees) == nil)
    }

    @Test("워크트리 하위 폴더로 cd해도 그 워크트리로 매칭된다")
    func 하위폴더도매칭() {
        let trees = [wt("/repo", branch: "main"), wt("/repo/.worktrees/feat", branch: "feat")]
        let target = WorktreeMove.target(cwd: "/repo/.worktrees/feat/src/app", projectPath: "/repo", worktrees: trees)
        #expect(target?.path == "/repo/.worktrees/feat")
    }

    @Test("중첩 워크트리는 가장 깊은 것을 고른다")
    func 가장깊은워크트리() {
        let trees = [wt("/repo", branch: "main"), wt("/repo/nested", branch: "n")]
        let target = WorktreeMove.target(cwd: "/repo/nested/x", projectPath: "/other", worktrees: trees)
        #expect(target?.path == "/repo/nested")
    }

    @Test("이름만 겹치는 형제 워크트리로 오판하지 않는다")
    func 접두사오판방지() {
        let trees = [wt("/repo/wt/feat", branch: "feat"), wt("/repo/wt/feat-2", branch: "feat-2")]
        let target = WorktreeMove.target(cwd: "/repo/wt/feat-2/src", projectPath: "/repo", worktrees: trees)
        #expect(target?.path == "/repo/wt/feat-2")
    }

    @Test("어느 워크트리에도 없거나 cwd가 없으면 이동 대상이 없다")
    func 매칭없음() {
        let trees = [wt("/repo", branch: "main")]
        #expect(WorktreeMove.target(cwd: "/somewhere/else", projectPath: "/repo", worktrees: trees) == nil)
        #expect(WorktreeMove.target(cwd: nil, projectPath: "/repo", worktrees: trees) == nil)
    }
}
