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
        // 5개 = remain-on-exit · base-index · pane-base-index · status · new-session 앞.
        #expect(args().filter { $0 == ";" }.count == 5)
    }

    @Test func pane_base_index를_0으로_new_session보다_먼저_강제한다() {
        // 사용자 ~/.tmux.conf의 pane-base-index 1이면 pane이 1이 돼 capture(`:.0`)·parsePanes(pane 0)가
        // 통째로 깨진다(빈 로그·오상태). new-session 앞에서 0으로 강제해야 만들어지는 pane이 0이다.
        let a = args()
        let opt = a.firstIndex(of: "pane-base-index")
        let create = a.firstIndex(of: "new-session")
        #expect(opt != nil && create != nil)
        #expect(opt! < create!)
        // 값이 바로 뒤에 0으로 온다.
        #expect(a[opt! + 1] == "0")
        #expect(a.contains("base-index")) // 윈도우 인덱스도 함께 0
    }

    @Test func 명령은_인터랙티브_로그인_셸로_감싸_인자로_넘긴다() {
        // 배열로 넘기므로 명령에 따옴표·공백이 섞여도 셸 인용이 필요 없다(`.app`은 PATH를 상속 못 한다).
        // `-i`가 빠지면 `.zshrc`를 안 읽어(로그인 비인터랙티브는 `.zprofile`만) nvm·PNPM_HOME 류의
        // PATH가 사라진다 — 탭에서는 되는 명령이 서비스로 돌리면 즉사하는 불일치의 원인.
        let expected = ["new-session", "-d", "-s", "muxa__p1__svc__s1",
                        "-c", "/tmp/proj", "/bin/zsh", "-l", "-i", "-c", "pnpm dev"]
        #expect(Array(args().suffix(expected.count)) == expected)
    }
}
