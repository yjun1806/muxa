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
        #expect(cmd.contains("new-session -d -A -s 'muxa__p1__term__t1' -c '/repo'"))
        #expect(cmd.contains("attach -t '=muxa__p1__term__t1'"))
    }

    /// runCommand 없으면 new-session은 baked 명령 없이 기본 셸로 뜬다(일반/복원 탭 불변).
    @Test func runCommand가_없으면_baked_명령을_안_붙인다() {
        #expect(!startCmd().contains("-lc"))
    }

    /// Claude 버튼 경로 — runCommand는 new-session에 **로그인 셸(`-lc`)로 실행 + 이후 대화형 셸**로 굽힌다.
    /// 로그인 셸이라야 .zprofile이 PATH를 세워 `~/.local/bin`의 claude를 찾는다(.app 빈약 PATH 대응).
    /// 프롬프트 타이핑이 아니라 pane 프로세스라 send-keys·타이밍이 전혀 없다.
    @Test func runCommand는_로그인셸로_굽고_이후_대화형셸로_떨어진다() {
        let cmd = TerminalSession.startCommand(
            tmux: "/opt/homebrew/bin/tmux", socket: "muxa",
            session: TerminalSession.name(projectId: "p1", tabId: "t1"),
            cwd: "/repo", runCommand: "claude")
        // 로그인 셸로 실행 + 끝나면 대화형 셸(탭 생존)
        #expect(cmd.contains(#"-lc '\''claude'\''; exec -l "${SHELL:-/bin/zsh}"#))
        // baked 명령은 new-session에 붙고 attach는 그대로다.
        #expect(cmd.contains("new-session -d -A -s 'muxa__p1__term__t1'"))
        #expect(cmd.contains("attach -t '=muxa__p1__term__t1'"))
    }

    /// 전역은 `on`이다(서비스가 죽은 뒤 로그를 읽어야 하므로). 터미널에 그대로 두면 `exit`를 쳐도
    /// pane이 죽은 채 남아 탭이 안 닫힌다. `-t`는 생략한다 — 명령 목록에서 방금 만든 세션이 현재
    /// 세션이라 거기 걸리고(실측), 세션명을 한 번 덜 반복해 줄 길이를 아낀다(§한_줄은_1024를_넘지_않는다).
    @Test func 터미널_세션은_remain_on_exit를_끈다() {
        let cmd = startCmd()
        #expect(cmd.contains("';' set-option remain-on-exit off ';'"))
        #expect(!cmd.contains("set-option -g remain-on-exit")) // 전역을 끄면 서비스 로그 보존이 깨진다
    }

    /// 도크·서비스가 켠 `-g mouse on`(서버 전역)이 공유 소켓을 타고 터미널 탭까지 새어들면 드래그가
    /// tmux copy-mode로 잡혀 뗄 때 선택이 풀린다(복사 불가). 이 세션만 per-session으로 mouse를 꺼
    /// 순정 ghostty 선택으로 되돌린다. **`-g`로 끄면 안 된다** — 서비스 도크 로그 스크롤이 죽는다.
    @Test func 터미널_세션은_mouse를_끈다() {
        let cmd = startCmd()
        #expect(cmd.contains("';' set-option mouse off ';'"))
        #expect(!cmd.contains("set-option -g mouse")) // 전역을 끄면 서비스 도크 마우스 스크롤이 깨진다
    }

    /// **한 줄이 1024바이트(tty 정규 모드의 `MAX_CANON`)를 넘으면 명령이 통째로 죽는다** —
    /// 넘친 뒤엔 끝의 개행까지 버려져 셸이 그 줄을 영영 실행하지 않고, 화면엔 에코만 남고 멈춘다.
    /// 실제로 그렇게 터졌다: 개발빌드 슬러그가 소켓·지원경로에 붙으면서 1150바이트가 됐다.
    /// tmux 호출을 여섯 번에서 한 번으로 합쳐 고쳤고, 다시 늘어나지 않게 여기서 못 박는다.
    ///
    /// 입력은 현실적인 최악값이다 — 긴 워크트리 슬러그가 소켓·지원경로에 모두 박히고, 세션명은
    /// UUID 두 개(76자)이며, 홈 경로도 짧지 않다.
    @Test func 한_줄은_1024를_넘지_않는다() {
        let uuid = "3DBD532E-0DCD-4966-9261-10B4B6BCBE0A" // 36자 — 실제 id와 같은 길이
        let slug = "muxa-services-some-long-worktree-name-a1b2c3"
        let session = TerminalSession.name(projectId: uuid, tabId: uuid)
        let sock = "/Users/some-longish-name/Library/Application Support/muxa-dev-some-long-worktree-name-a1b2c3/sockets/muxa-30354.sock"
        let cmd = TerminalSession.startCommand(
            tmux: "/opt/homebrew/bin/tmux", socket: slug, session: session,
            cwd: "/Users/some-longish-name/Documents/private/muxa/.claude/worktrees/some-long-worktree-name",
            env: ["MUXA_SOCK": sock,
                  "MUXA_SURFACE_ID": uuid,
                  "MUXA_TAB_ID": uuid])
        // `clear; ` 접두와 끝 개행까지 셸에 들어간다(TermView.initialCommand) — 그 몫도 남겨 둔다.
        #expect(cmd.utf8.count + "clear; \n".utf8.count < 1024)
    }

    /// 이게 없으면 tmux가 안쪽 OSC를 삼켜 cwd 추적·완료 배지·알림이 통째로 죽는다(실측).
    @Test func passthrough를_켠다() {
        #expect(startCmd().contains("set-option -g allow-passthrough on"))
    }

    /// tmux는 기본으로 extended keys를 끈다 — 그러면 안쪽 TUI(Claude Code 등)가 kitty 키보드
    /// 프로토콜을 요청해도 tmux가 Shift+Enter를 그냥 Enter로 뭉개 줄바꿈 입력이 안 된다.
    /// 바깥 터미널(ghostty, TERM=xterm-ghostty)이 extkeys를 지원한다는 것도 알려줘야
    /// tmux가 밖으로 modifyOtherKeys를 요청해 조합을 구분해 받는다.
    @Test func extended_keys를_켠다() {
        let cmd = startCmd()
        #expect(cmd.contains("set-option -s extended-keys on"))
        #expect(cmd.contains("set-option -sa terminal-features 'xterm*:extkeys'"))
    }

    /// zsh에서 `=word`는 명령 경로로 치환되는 EQUALS 확장 — 인용을 빼면 세션명을 명령으로 착각한다.
    @Test func 타겟은_인용된다() {
        #expect(!startCmd().contains("attach -t =muxa"))
    }

    /// cwd·tmux 경로는 외부 입력이다 — 아포스트로피 든 경로(`~/Bob's app`)에서 따옴표가 조기에 닫히거나
    /// `'; rm … ; '`로 명령이 주입되면 안 된다. POSIX 관용구 `'\''`로 탈출한다.
    @Test func 아포스트로피_든_경로도_안전하게_인용된다() {
        let cmd = TerminalSession.startCommand(
            tmux: "/opt/homebrew/bin/tmux", socket: "muxa",
            session: "muxa__p__term__t", cwd: "/Users/yj/Bob's app")
        #expect(cmd.contains(#"-c '/Users/yj/Bob'\''s app'"#))
        // 탈출된 아포스트로피 밖으로 새어나온 raw `'s app`이 없어야 한다(따옴표 조기 종료 방지).
        #expect(!cmd.contains(#"Bob's app'"#))
    }

    @Test func 주입_시도가_담긴_경로는_통째로_한_인자로_인용된다() {
        let cmd = TerminalSession.startCommand(
            tmux: "/opt/homebrew/bin/tmux", socket: "muxa",
            session: "muxa__p__term__t", cwd: "/x'; touch pwned; '")
        // 주입 페이로드가 인용 밖으로 나와 독립 명령이 되지 않는다.
        #expect(cmd.contains(#"'/x'\''; touch pwned; '\'''"#))
        #expect(!cmd.contains("; touch pwned; 2>/dev/null"))
    }

    /// exec로 태우면 detach하는 순간 셸까지 죽어 탭이 사라진다. 프롬프트로 돌아와야 탭이 살아남는다.
    /// (`startCommand` 자체는 exec를 안 쓴다 — 셸 유지는 `execCommand`의 후행 `exec -l $SHELL`이 맡는다.)
    @Test func exec로_태우지_않는다() {
        #expect(!startCmd().contains("exec "))
    }

    // MARK: command 필드 래퍼(execCommand) — 초기입력 주입 대신 직접 exec(번쩍임 제거)

    /// ghostty는 `command`를 `exec -l <cmd>`로 태워 단일 실행 파일만 받는다 — `;`로 이어진 복합 tmux
    /// 명령은 `/bin/sh -c`로 감싸지 않으면 pane이 즉사한다.
    @Test func execCommand는_sh_c로_감싼다() {
        #expect(TerminalSession.execCommand("tmux -L muxa attach").hasPrefix("/bin/sh -c '"))
    }

    /// attach가 detach되거나 끝나도 살아있는 로그인 셸이 남아 탭이 죽지 않는다($SHELL, 미설정 시 zsh).
    @Test func execCommand는_로그인_셸을_남긴다() {
        #expect(TerminalSession.execCommand("tmux attach").contains(#"exec -l "${SHELL:-/bin/zsh}""#))
    }

    /// inner는 인용을 많이 쓴다(startCommand). 그 작은따옴표가 바깥 `/bin/sh -c '…'`의 따옴표를
    /// 조기에 닫지 않아야 한다 — POSIX `'\''`로 탈출된다.
    @Test func execCommand는_inner의_따옴표를_탈출한다() {
        let wrapped = TerminalSession.execCommand("attach -t '=sess'")
        #expect(wrapped.contains(#"'\''=sess'\''"#))
        #expect(!wrapped.contains("attach -t '=sess'; exec")) // raw가 그대로 새어나오지 않는다
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

    // MARK: 목록에 뜰 이름 — "무엇을 되찾는지"

    /// **래퍼 셸이 아니라 진짜 작업 이름이 떠야 한다.** "zsh로 끝나지 않는 것"으로 고르면
    /// `zsh (kiro-cli-term)`이 먼저 잡혀 정작 돌고 있는 빌드 대신 셸 이름이 뜬다(실측으로 걸렸다).
    @Test func 목록에는_진짜_작업이_뜬다() {
        #expect(TerminalSession.workLabel(foreground: ["zsh (kiro-cli-term)", "/bin/zsh", "sleep"]) == "sleep")
        #expect(TerminalSession.workLabel(foreground: ["zsh", "/usr/local/bin/pnpm"]) == "pnpm")
        #expect(TerminalSession.workLabel(foreground: ["-zsh", "claude"]) == "claude")
    }

    @Test func 셸뿐이면_이름이_없다() {
        #expect(TerminalSession.workLabel(foreground: ["zsh (kiro-cli-term)", "/bin/zsh"]) == nil)
        #expect(TerminalSession.workLabel(foreground: []) == nil)
    }

    /// **버전 이름을 집으면 안 된다.** claude는 자기 자신을 버전 바이너리로 exec해서 트리에
    /// `2.1.207` 같은 프로세스가 생긴다. 그걸 집으면 목록에 "2.1.207"이 떠서 뭐가 도는지 모른다(실측).
    @Test func 버전_이름_대신_진짜_이름을_집는다() {
        #expect(TerminalSession.workLabel(foreground: ["zsh", "claude", "2.1.207"]) == "claude")
        #expect(TerminalSession.workLabel(foreground: ["zsh", "2.1.207", "claude"]) == "claude")
        #expect(TerminalSession.workLabel(foreground: ["zsh", "node", "1.2.3"]) == "node")
    }

    /// 버전만 있으면(진짜 이름을 못 찾으면) 이름이 없다 — 호출부가 "작업"으로 폴백한다.
    @Test func 버전만_있으면_이름이_없다() {
        #expect(TerminalSession.workLabel(foreground: ["zsh", "2.1.207"]) == nil)
    }
}
