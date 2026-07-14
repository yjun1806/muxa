import Testing
@testable import muxa

/// git 셸아웃 인자 조립(SSOT) — 비ASCII 경로가 8진 이스케이프로 나오지 않게 quotepath를 항상 끈다.
struct GitArgsTests {
    @Test("모든 git 명령 앞에 core_quotepath=false가 붙는다")
    func quotepath가항상붙는다() {
        #expect(GitService.gitArgs(["status", "--porcelain=v1"])
            == ["git", "-c", "core.quotepath=false", "status", "--porcelain=v1"])
    }

    @Test("설정 플래그는 하위 명령보다 앞에 온다 (git은 -c를 명령 앞에서만 받는다)")
    func 설정플래그는명령앞에온다() {
        let args = GitService.gitArgs(["add", "--", "한글.txt"])
        #expect(args.first == "git")
        #expect(args[1] == "-c")
        #expect(args.last == "한글.txt")
    }

    @Test("인자가 없어도 조립된다")
    func 빈인자() {
        #expect(GitService.gitArgs([]) == ["git", "-c", "core.quotepath=false"])
    }
}
