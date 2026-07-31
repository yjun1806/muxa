import Testing
@testable import muxa

/// Workspace 헬퍼 순수 함수(basename·displayPath) 검증.
struct WorkspaceTests {
    @Test func basename은_마지막_구성요소를_돌려준다() {
        #expect(basename("/a/b/c") == "c")
        #expect(basename("/a/b/c/") == "c")   // trailing slash 무시
        #expect(basename("single") == "single")
    }

    @Test func displayPath는_홈을_물결로_줄인다() {
        #expect(displayPath("/Users/x/proj", home: "/Users/x") == "~/proj")
        #expect(displayPath("/other/path", home: "/Users/x") == "/other/path")
        #expect(displayPath(nil, home: "/Users/x") == "")
    }

    @Test func 새_워크스페이스는_메인_프로젝트_하나를_갖는다() {
        let ws = createWorkspace(path: "/repo")
        #expect(ws.projects.count == 1)
        #expect(ws.activeProjectId == ws.projects[0].id)
        #expect(ws.projects[0].path == nil) // 메인 프로젝트는 워크스페이스 경로 상속(nil)
        #expect(ws.name == "repo")
    }
}
