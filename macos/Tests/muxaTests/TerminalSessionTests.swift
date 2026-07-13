import Testing
@testable import muxa

/// 터미널 탭의 tmux 세션 규약(순수) — 서비스 세션과 **같은 소켓에 살되 섞이면 안 된다**.
///
/// 서비스 GC(`ServiceSession.orphans`)는 "등록(Project.services)에 없는 muxa 세션 = 고아"로 판정해
/// **죽인다**. 터미널 세션이 그 판정에 걸리면 멀쩡히 돌던 셸이 전부 죽는다.
struct TerminalSessionTests {
    @Test func 세션명은_term_네임스페이스를_쓴다() {
        let name = TerminalSession.name(projectId: "p1", tabId: "t1")
        #expect(name == "muxa__p1__term__t1")
    }

    @Test func 자기_세션은_파싱된다() {
        let parsed = TerminalSession.parse("muxa__p1__term__t1")
        #expect(parsed?.projectId == "p1")
        #expect(parsed?.tabId == "t1")
    }

    @Test func 서비스_세션은_터미널로_파싱되지_않는다() {
        #expect(TerminalSession.parse("muxa__p1__svc1") == nil)
    }

    @Test func 남의_tmux_세션은_파싱되지_않는다() {
        #expect(TerminalSession.parse("my-important-work") == nil)
        #expect(TerminalSession.parse("other__p1__term__t1") == nil)
    }

    /// **회귀 방지의 핵심.** 서비스 고아 판정이 터미널 세션을 건드리면 안 된다.
    @Test func 서비스_고아판정이_터미널_세션을_죽이지_않는다() {
        let sessions = [
            "muxa__p1__svc1",            // 등록된 서비스
            "muxa__p1__svc2",            // 등록 없는 서비스 → 고아
            "muxa__p1__term__t1",        // 터미널 → 절대 건드리면 안 됨
            "my-important-work",         // 남의 세션 → 절대 건드리면 안 됨
        ]
        let orphans = ServiceSession.orphans(sessions: sessions, liveServiceIds: ["svc1"],
                                             knownProjectIds: ["p1"])
        #expect(orphans == ["muxa__p1__svc2"])
    }

    /// 터미널 세션 고아 = 살아있는 탭에 없는 터미널 세션. 서비스는 입력에 있어도 건드리지 않는다.
    @Test func 터미널_고아판정은_자기_네임스페이스만_본다() {
        let sessions = [
            "muxa__p1__term__t1",   // 살아있는 탭
            "muxa__p1__term__t2",   // 닫힌 탭 → 고아
            "muxa__p1__svc1",       // 서비스 → 건드리지 않는다
            "my-important-work",    // 남의 세션 → 건드리지 않는다
        ]
        let orphans = TerminalSession.orphans(sessions: sessions,
                                              liveSessionNames: ["muxa__p1__term__t1"],
                                              knownProjectIds: ["p1"])
        #expect(orphans == ["muxa__p1__term__t2"])
    }

    @Test func 살아있는_세션이_없으면_아는_프로젝트의_터미널_세션만_고아다() {
        let orphans = TerminalSession.orphans(
            sessions: ["muxa__p1__term__t1", "muxa__p2__term__t9"],
            liveSessionNames: [], knownProjectIds: ["p1", "p2"])
        #expect(orphans.sorted() == ["muxa__p1__term__t1", "muxa__p2__term__t9"])
    }

    /// **다른 muxa 인스턴스의 세션은 건드리지 않는다.** 같은 tmux 소켓을 공유하므로,
    /// 내 state에 없는 프로젝트의 터미널 세션은 남의 것이다(서비스 GC와 같은 가드).
    @Test func 모르는_프로젝트의_터미널_세션은_남긴다() {
        let orphans = TerminalSession.orphans(
            sessions: ["muxa__mine__term__t1", "muxa__theirs__term__t2"],
            liveSessionNames: [], knownProjectIds: ["mine"])
        #expect(orphans == ["muxa__mine__term__t1"])
    }

    @Test func 아는_프로젝트가_없으면_아무것도_지우지_않는다() {
        let orphans = TerminalSession.orphans(
            sessions: ["muxa__p1__term__t1"], liveSessionNames: [], knownProjectIds: [])
        #expect(orphans.isEmpty)
    }

    // MARK: 기동 명령 — 빠지면 조용히 깨지는 것들을 고정한다

    private func startCmd() -> String {
        TerminalSession.startCommand(tmux: "/opt/homebrew/bin/tmux", socket: "muxa",
                                     session: TerminalSession.name(projectId: "p1", tabId: "t1"),
                                     cwd: "/repo")
    }

    @Test func 기동명령은_세션이_없으면_만들고_있으면_붙는다() {
        let cmd = startCmd()
        #expect(cmd.contains("new-session -d -s 'muxa__p1__term__t1' -c '/repo'"))
        #expect(cmd.contains("attach -t '=muxa__p1__term__t1'"))
    }

    /// 전역은 `on`이다(서비스가 죽은 뒤 로그를 읽어야 하므로). 터미널에 그대로 두면 `exit`를 쳐도
    /// pane이 죽은 채 남아 탭이 안 닫힌다.
    @Test func 터미널_세션은_remain_on_exit를_끈다() {
        #expect(startCmd().contains("set-option -t 'muxa__p1__term__t1' remain-on-exit off"))
    }

    /// 이게 없으면 tmux가 안쪽 OSC를 삼켜 cwd 추적·완료 배지·알림이 통째로 죽는다(실측).
    @Test func passthrough를_켠다() {
        #expect(startCmd().contains("set-option -g allow-passthrough on"))
    }

    /// zsh에서 `=word`는 명령 경로로 치환되는 EQUALS 확장 — 인용을 빼면 세션명을 명령으로 착각한다.
    @Test func 타겟은_인용된다() {
        #expect(!startCmd().contains("attach -t =muxa"))
    }

    /// exec로 태우면 detach하는 순간 셸까지 죽어 탭이 사라진다. 프롬프트로 돌아와야 탭이 살아남는다.
    @Test func exec로_태우지_않는다() {
        #expect(!startCmd().contains("exec "))
    }

    /// tmux는 기본으로 자기 제목(= attach 명령줄)을 내보내 탭 이름이 그걸로 굳는다(실측).
    /// 안쪽 셸의 폴더명을 대신 전파해 자동 명명을 되살린다.
    @Test func 탭_제목을_폴더명으로_되돌린다() {
        let cmd = startCmd()
        #expect(cmd.contains("set-titles on"))
        #expect(cmd.contains("set-titles-string '#{b:pane_current_path}'"))
    }

    /// tmux 세션의 셸은 tmux **서버**의 환경을 상속한다 — ghostty가 띄운 바깥 셸의 env를 못 받는다.
    /// `-e`로 심지 않으면 MUXA_TAB_ID가 없어 훅 알림이 어느 탭인지 못 찾고, rc 스니펫도 안 돈다(실측).
    @Test func 세션에_env를_심는다() {
        let cmd = TerminalSession.startCommand(
            tmux: "tmux", socket: "muxa",
            session: TerminalSession.name(projectId: "p1", tabId: "t1"), cwd: "/repo",
            env: ["MUXA_TAB_ID": "t1", "MUXA_SOCK": "/tmp/muxa.sock"])
        #expect(cmd.contains("-e 'MUXA_TAB_ID=t1'"))
        #expect(cmd.contains("-e 'MUXA_SOCK=/tmp/muxa.sock'"))
    }

    // MARK: 훅 라우팅 역매핑 — 복원해도 알림이 올바른 탭에 꽂힌다

    /// 복원하면 tabId가 새로 발급되지만 tmux 세션 안 셸의 MUXA_TAB_ID는 **처음 id** 그대로다.
    /// 세션명에 박힌 옛 id로 현재 탭을 되찾지 못하면 알림이 조용히 사라진다.
    @Test func 옛_tabId를_현재_탭으로_되짚는다() {
        let sessions = ["새tab": TerminalSession.name(projectId: "p1", tabId: "옛tab")]
        #expect(TerminalSession.resolve(incomingTabId: "옛tab", sessionsByTab: sessions) == "새tab")
    }

    @Test func 살아있는_tabId는_그대로_쓴다() {
        let sessions = ["t1": TerminalSession.name(projectId: "p1", tabId: "t1")]
        #expect(TerminalSession.resolve(incomingTabId: "t1", sessionsByTab: sessions) == "t1")
    }

    @Test func 모르는_tabId는_nil() {
        let sessions = ["t1": TerminalSession.name(projectId: "p1", tabId: "t1")]
        #expect(TerminalSession.resolve(incomingTabId: "모르는id", sessionsByTab: sessions) == nil)
    }

    @Test func tmux를_안_쓰면_되짚을_것이_없다() {
        #expect(TerminalSession.resolve(incomingTabId: "t1", sessionsByTab: [:]) == nil)
    }

    // MARK: 탭 닫기 — 죽일지 남길지

    /// 셸만 있는 탭은 되찾을 작업이 없다 — 남기면 유령만 쌓인다.
    @Test func 셸만_있으면_죽인다() {
        #expect(!TerminalSession.shouldDetach(foreground: ["zsh"]))
        #expect(!TerminalSession.shouldDetach(foreground: ["-zsh"])) // 로그인 셸
        #expect(!TerminalSession.shouldDetach(foreground: ["/bin/zsh", "login"]))
        #expect(!TerminalSession.shouldDetach(foreground: ["bash", "fish"]))
    }

    /// 돌던 작업이 있으면 남긴다 — ⌘W를 잘못 눌렀다고 30분 돌던 빌드가 즉사하면 안 된다.
    @Test func 작업이_돌고_있으면_남긴다() {
        #expect(TerminalSession.shouldDetach(foreground: ["zsh", "claude"]))
        #expect(TerminalSession.shouldDetach(foreground: ["node"]))
        #expect(TerminalSession.shouldDetach(foreground: ["zsh", "zsh", "sleep"])) // 셸이 여러 겹이어도
    }

    /// **래퍼 셸에 속지 않는다.** 사용자 zsh가 `kiro-cli-term` 같은 래퍼로 감싸져 있으면
    /// tmux의 pane_current_command는 영원히 "zsh"라 답한다 — 안에서 빌드가 돌아도.
    /// TTY 포그라운드를 직접 보므로 진짜 작업을 놓치지 않는다(실측으로 걸린 함정).
    @Test func 래퍼_셸에_속지_않는다() {
        #expect(!TerminalSession.shouldDetach(foreground: ["zsh (kiro-cli-term)", "/bin/zsh"]))
        #expect(TerminalSession.shouldDetach(foreground: ["zsh (kiro-cli-term)", "/bin/zsh", "sleep"]))
    }

    /// 아무것도 안 돌면 죽인다 — 쌓이는 쪽이 잃는 쪽보다 나쁘다(유령은 눈에 안 보인다).
    @Test func 아무것도_없으면_죽인다() {
        #expect(!TerminalSession.shouldDetach(foreground: []))
        #expect(!TerminalSession.shouldDetach(foreground: ["", "  "]))
    }
}
