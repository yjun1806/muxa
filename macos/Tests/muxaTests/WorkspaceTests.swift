import XCTest
@testable import muxa

/// Workspace 헬퍼 순수 함수(basename·displayPath) 검증.
final class WorkspaceTests: XCTestCase {
    func testBasename() {
        XCTAssertEqual(basename("/a/b/c"), "c")
        XCTAssertEqual(basename("/a/b/c/"), "c")   // trailing slash 무시
        XCTAssertEqual(basename("single"), "single")
    }

    func testDisplayPathAbbreviatesHome() {
        XCTAssertEqual(displayPath("/Users/x/proj", home: "/Users/x"), "~/proj")
        XCTAssertEqual(displayPath("/other/path", home: "/Users/x"), "/other/path")
        XCTAssertEqual(displayPath(nil, home: "/Users/x"), "")
    }

    func testCreateWorkspaceHasSingleMainProject() {
        let ws = createWorkspace(path: "/repo")
        XCTAssertEqual(ws.projects.count, 1)
        XCTAssertEqual(ws.activeProjectId, ws.projects[0].id)
        XCTAssertNil(ws.projects[0].path) // 메인 프로젝트는 워크스페이스 경로 상속(nil)
        XCTAssertEqual(ws.name, "repo")
    }
}
