import Foundation
import Testing
@testable import muxa

/// 서비스 기동 명령의 **순서**가 곧 정확성이다.
///
/// `remain-on-exit`가 pane보다 늦게 걸리면, 서버가 없던 상태에서 첫 서비스가 즉사할 때
/// (포트 선점·오타 — 가장 흔한 실패) pane이 증발해 exit code·로그·알림이 통째로 사라진다.
/// tmux 서버가 이미 살아 있으면 멀쩡해서 **간헐적으로만** 터진다.
struct TmuxStartArgsTests {
    private func args() -> [String] {
        TmuxService.startArgs(session: "muxa__p1__svc__s1", cwd: "/tmp/proj",
                              shell: "/bin/zsh", command: "pnpm dev")
    }

    @Test func remain_on_exit가_new_session보다_먼저_걸린다() {
        let a = args()
        let option = a.firstIndex(of: "remain-on-exit")
        let create = a.firstIndex(of: "new-session")
        #expect(option != nil && create != nil)
        #expect(option! < create!)
    }

    @Test func 서버를_먼저_띄운다() {
        // 옵션만 걸면 세션이 없는 서버는 곧장 꺼져 설정이 날아간다 — start-server가 맨 앞이어야 한다.
        #expect(args().first == "start-server")
    }

    @Test func 한_번의_호출에_세미콜론으로_이어_붙인다() {
        // 명령을 나눠 보내면 그 사이에 pane이 죽을 수 있다. tmux가 명령 목록을 순차 처리하도록
        // `;`(그 자체가 하나의 인자)로 잇는다 — 셸을 안 거치므로 인용이 필요 없다.
        #expect(args().filter { $0 == ";" }.count == 3)
    }

    @Test func 명령은_로그인_셸로_감싸_인자로_넘긴다() {
        // 배열로 넘기므로 명령에 따옴표·공백이 섞여도 셸 인용이 필요 없다(`.app`은 PATH를 상속 못 한다).
        let expected = ["new-session", "-d", "-s", "muxa__p1__svc__s1",
                        "-c", "/tmp/proj", "/bin/zsh", "-l", "-c", "pnpm dev"]
        #expect(Array(args().suffix(expected.count)) == expected)
    }
}
