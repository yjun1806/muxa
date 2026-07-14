import Testing
@testable import muxa

/// 첫 워크스페이스 경로 판정 — 번들 실행(Finder/Dock)의 cwd는 `/`라 그대로 쓰면 첫 화면이 루트가 된다.
struct InitialWorkspacePathTests {
    @Test("설정된 기본 경로가 최우선이다")
    func 설정우선() {
        let path = InitialWorkspacePath.resolve(configured: "/Users/x/code", currentDir: "/Users/x/repo",
                                                isBundled: false, home: "/Users/x")
        #expect(path == "/Users/x/code")
    }

    @Test("번들 실행이면 cwd를 무시하고 홈으로 간다")
    func 번들은홈() {
        let path = InitialWorkspacePath.resolve(configured: nil, currentDir: "/",
                                                isBundled: true, home: "/Users/x")
        #expect(path == "/Users/x")
    }

    @Test("번들 실행은 cwd가 멀쩡해도 홈이다")
    func 번들은cwd무시() {
        let path = InitialWorkspacePath.resolve(configured: nil, currentDir: "/Users/x/repo",
                                                isBundled: true, home: "/Users/x")
        #expect(path == "/Users/x")
    }

    @Test("bare 개발 실행은 현재 디렉터리를 쓴다")
    func 개발실행cwd() {
        let path = InitialWorkspacePath.resolve(configured: nil, currentDir: "/Users/x/repo",
                                                isBundled: false, home: "/Users/x")
        #expect(path == "/Users/x/repo")
    }

    @Test("cwd가 루트면 bare 실행이어도 홈으로 폴백한다")
    func 루트폴백() {
        let path = InitialWorkspacePath.resolve(configured: nil, currentDir: "/",
                                                isBundled: false, home: "/Users/x")
        #expect(path == "/Users/x")
    }

    @Test("빈 설정값은 없는 것으로 본다")
    func 빈설정무시() {
        let path = InitialWorkspacePath.resolve(configured: "", currentDir: nil,
                                                isBundled: true, home: "/Users/x")
        #expect(path == "/Users/x")
    }
}
