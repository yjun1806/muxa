import Testing
@testable import muxa

/// 세션 cwd의 "임자"(가장 구체적인 프로젝트) 판정(순수) — 링크 카드(D31)의 대상 판정.
struct WorktreeLinkTests {
    @Test("cwd를 담는 가장 구체적인 프로젝트가 임자다(루트가 하위 워크트리를 가로채지 않는다)")
    func 임자는가장깊은프로젝트() {
        // 메인=레포 루트, feat=레포 하위 워크트리. cwd는 워크트리 안 → 임자는 feat(인덱스 1).
        #expect(WorktreeLink.owner(pwd: "/repo/.worktrees/feat",
                                   projectPaths: ["/repo", "/repo/.worktrees/feat"]) == 1)
    }

    @Test("cwd와 정확히 같은 경로도 임자다")
    func 정확일치() {
        #expect(WorktreeLink.owner(pwd: "/wt/feat", projectPaths: ["/wt/feat"]) == 0)
    }

    @Test("이름만 겹치는 형제 폴더는 임자가 아니다")
    func 접두사오판방지() {
        #expect(WorktreeLink.owner(pwd: "/wt/feat", projectPaths: ["/wt/feat-2"]) == nil)
    }

    @Test("담는 프로젝트가 없으면 임자도 없다")
    func 임자없음() {
        #expect(WorktreeLink.owner(pwd: "/somewhere/else", projectPaths: ["/repo"]) == nil)
    }

    @Test("뒤 슬래시가 있어도 같은 경로로 본다")
    func 뒤슬래시정규화() {
        #expect(WorktreeLink.owner(pwd: "/wt/feat", projectPaths: ["/wt/feat/"]) == 0)
    }

    @Test("루트(/) 프로젝트는 임자가 될 수 없다")
    func 루트는임자아님() {
        #expect(WorktreeLink.owner(pwd: "/repo/x", projectPaths: ["/"]) == nil)
    }

    @Test("빈 cwd는 임자를 못 가진다")
    func 빈cwd제외() {
        #expect(WorktreeLink.owner(pwd: "", projectPaths: ["/repo"]) == nil)
    }

    // MARK: pathIsInside — 경로 포함 판정(자동 승격의 "세션이 그 안에 있나" 신호)

    @Test("자신·하위 경로는 안이고, 형제 접두사는 밖이다")
    func 경로포함판정() {
        #expect(pathIsInside("/wt/feat", root: "/wt/feat"))
        #expect(pathIsInside("/wt/feat/apps/web", root: "/wt/feat"))
        #expect(!pathIsInside("/wt/feat-2", root: "/wt/feat"))
        #expect(!pathIsInside("/other", root: "/wt/feat"))
    }

    @Test("루트(/)와 빈 root는 항상 밖이다 — 전부 포함은 판정으로 무의미")
    func 루트빈경로제외() {
        #expect(!pathIsInside("/anything", root: "/"))
        #expect(!pathIsInside("/anything", root: ""))
    }

    @Test("뒤 슬래시가 있어도 같은 경로로 본다")
    func 포함판정뒤슬래시() {
        #expect(pathIsInside("/wt/feat/", root: "/wt/feat"))
        #expect(pathIsInside("/wt/feat", root: "/wt/feat/"))
    }
}
