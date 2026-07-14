import Testing
import Foundation
@testable import muxa

/// 영속 탭(∞)이 **아직 tmux 안에 있는가**를 pty의 포그라운드 이름만으로 판정한다.
///
/// `tmux attach` 중이면 바깥 pty의 포그라운드는 **항상 tmux 클라이언트 하나**다 — 안쪽에서 도는
/// 빌드·에이전트는 tmux가 따로 만든 pty에 살아서 바깥에선 안 보인다. 그래서 이 판정은 안쪽 내용에
/// 흔들리지 않는다. 셸 이름이 보인다는 건 attach가 끝나 프롬프트로 돌아왔다는 뜻이다
/// (`⌃b d` detach · 안쪽 `exit` · tmux 서버 죽음 — 셋 다 결과는 같다).
struct TmuxAttachTests {
    @Test func 포그라운드가_tmux면_붙어_있다() {
        #expect(TerminalSession.isAttached(foregroundName: "tmux"))
    }

    @Test func 절대경로로_잡혀도_tmux다() {
        // argv[0]이 실행 경로 그대로일 수 있다(homebrew 설치본).
        #expect(TerminalSession.isAttached(foregroundName: "/opt/homebrew/bin/tmux"))
    }

    @Test func 셸이_보이면_tmux_밖이다() {
        #expect(!TerminalSession.isAttached(foregroundName: "zsh"))
        #expect(!TerminalSession.isAttached(foregroundName: "-zsh")) // 로그인 셸
    }

    @Test func 안쪽_프로세스는_바깥_pty에_안_보인다() {
        // 만에 하나 tmux가 아닌 것이 포그라운드면(셸이든 무엇이든) attach는 끝난 것이다.
        // "claude가 돌고 있으니 살아 있다"고 봐주면 안 된다 — 그건 tmux 없이도 가능한 상태다.
        #expect(!TerminalSession.isAttached(foregroundName: "claude"))
    }

    @Test func pid를_못_읽으면_판정하지_않는다() {
        // 셸 스폰 직후엔 foreground pid가 아직 0이다(TermView가 재시도한다). 이 구간을 "끊김"으로
        // 다루면 탭을 만들자마자 ∞가 떨어진다 — 모를 땐 붙어 있다고 본다(보존적 판정).
        #expect(TerminalSession.isAttached(foregroundName: nil))
    }
}
