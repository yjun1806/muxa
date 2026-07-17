import Foundation

/// 터미널 탭을 tmux 세션에 담는 규약(순수) — 앱을 꺼도 셸·에이전트·빌드가 살아남게 한다(L3).
///
/// 서비스([[Service]])와 **같은 전용 소켓(`-L muxa`)에 살지만 네임스페이스가 다르다**:
///
///     서비스   muxa__<projectId>__<serviceId>
///     터미널   muxa__<projectId>__term__<tabId>
///
/// 이 분리가 중요한 이유: 서비스 고아 정리(`ServiceSession.orphans`)는 "등록에 없는 muxa 세션"을
/// **죽인다**. 터미널 세션이 그 판정에 걸리면 멀쩡히 돌던 셸이 전부 죽는다. `ServiceSession.parse`가
/// `__` 3조각만 인정하므로 4조각인 터미널 세션은 그 판정에서 자동으로 빠진다 — 그래도 우연에
/// 기대지 않도록 여기서 규약을 명시하고 테스트로 고정한다.
enum TerminalSession {
    /// 터미널 네임스페이스 표식. 서비스 세션과 조각 수가 달라 서로의 파서에 걸리지 않는다.
    static let marker = "term"

    static func name(projectId: String, tabId: String) -> String {
        [ServiceSession.prefix, projectId, marker, tabId].joined(separator: ServiceSession.separator)
    }

    /// muxa 소유 **터미널** 세션명만 분해한다. 서비스 세션·남의 세션은 nil.
    static func parse(_ sessionName: String) -> (projectId: String, tabId: String)? {
        let parts = sessionName.components(separatedBy: ServiceSession.separator)
        guard parts.count == 4,
              parts[0] == ServiceSession.prefix,
              parts[2] == marker,
              !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return (parts[1], parts[3])
    }

    /// 이 탭의 셸을 tmux 세션 안에서 띄우는 명령(순수). `TermView.initialCommand`로 셸에 주입한다.
    ///
    /// 한 줄에 네 가지를 순서대로 한다 — **셋 다 빠지면 조용히 깨진다**:
    ///  1. `new-session -d` — 없으면 만들고, 있으면 실패(무시)한다. 앱을 껐다 켜도 같은 이름이면 그대로 붙는다.
    ///  2. `remain-on-exit off` — 서버 전역은 `on`이다(서비스가 죽은 뒤 exit code·로그를 읽어야 하므로).
    ///     터미널에 그대로 두면 사용자가 `exit`를 쳐도 pane이 죽은 채 남아 탭이 안 닫히고 세션이 쌓인다.
    ///  3. `allow-passthrough on` — tmux는 안쪽 OSC를 자체 소비한다. 이걸 켜야 셸 통합이
    ///     `\ePtmux;…\e\\`로 감싼 OSC 7(cwd)·133(완료)이 muxa까지 나온다. 없으면 경로 추적과
    ///     완료 배지·알림이 통째로 죽는다(실측).
    ///  4. `attach` — 붙는다. **exec를 쓰지 않는다**: detach하면 셸 프롬프트로 돌아와 탭이 살아남는다.
    ///
    /// zsh에서 `=word`는 명령 경로로 치환되는 EQUALS 확장이라 타겟은 반드시 인용한다(서비스 attach와 동일).
    ///
    /// **한 줄은 1024바이트(`MAX_CANON`)를 넘으면 안 된다 — 넘으면 명령이 통째로 죽는다.**
    /// 이 문자열은 셸의 stdin으로 들어가는데(`TermView.initialCommand`), 그때 tty는 아직 정규 모드다.
    /// 정규 모드의 한 줄 버퍼는 1024바이트이고, 넘친 뒤엔 **끝의 개행까지 버려져** 셸이 그 줄을 영영
    /// 실행하지 않는다. 화면엔 에코된 명령만 남고 멈춘다(실측 — 개발빌드 슬러그가 소켓·지원경로 이름에
    /// 붙으면서 1150바이트가 됐다). 그래서 tmux 호출을 **한 번으로 합치고**(실행 파일 경로 + 소켓 이름이
    /// 여섯 번 반복되던 것을 한 번으로) 세션명 반복도 줄인다 — 지금은 ~600바이트다.
    /// 값이 길어질 여지(홈 경로·워크트리 이름)가 있으므로 **길이는 테스트로 못 박는다**.
    ///
    /// - Parameter session: **세션명을 그대로 받는다.** 복원된 탭은 저장된 이름을 이어받아야 하는데,
    ///   여기서 tabId로 재조립하면 새로 발급된 id로 엉뚱한 세션을 만든다(§tmuxSession).
    /// - Parameter env: 세션 안 셸에 심을 환경변수(`-e`). **비우면 훅과 셸 통합이 통째로 죽는다** —
    ///   tmux 세션의 셸은 tmux **서버**의 환경을 상속하지, ghostty가 띄운 바깥 셸의 env를 받지 않는다.
    ///   그래서 MUXA_TAB_ID·MUXA_SOCK이 없어 `muxa notify`가 어느 탭인지 못 찾고(알림·배지 소실),
    ///   rc 스니펫도 조건이 안 맞아 OSC를 안 쏜다(cwd 추적 소실). 실측으로 확인한 실패다.
    static func startCommand(tmux: String, socket: String, session: String, cwd: String,
                             env: [String: String] = [:]) -> String {
        // -e는 **세션을 새로 만들 때만** 적용된다(이미 있으면 무시). 복원된 세션의 셸에는 옛 tabId가
        // 남아 있는데, 그건 세션명으로 되짚어 현재 탭을 찾는다(§resolve).
        // 값(경로·env)은 외부 입력이므로 모두 탈출한다 — 아포스트로피 든 경로(`~/Bob's app`)나 주입 차단.
        let envArgs = env.keys.sorted().map { " -e \(ShellQuote.single("\($0)=\(env[$0]!)"))" }.joined()
        let q = ShellQuote.single(session)
        // tmux는 한 번의 실행에서 `;`로 여러 명령을 잇는다. `;`는 셸이 먹지 않게 인용한다.
        // `remain-on-exit`는 **-t를 생략**한다 — 명령 목록에서 방금 만든 세션이 현재 세션이 되므로
        // 세션명(76바이트)을 한 번 덜 반복한다(실측: 전역 `on`은 그대로 유지돼 서비스 로그 보존이 안 깨진다).
        let cmds = [
            // 서버 전역 — tmux는 안쪽 OSC를 자체 소비한다. 켜야 셸 통합이 감싼 OSC 7(cwd)·133(완료)이
            // muxa까지 나온다. 없으면 경로 추적·완료 배지·알림이 통째로 죽는다(실측).
            "set-option -g allow-passthrough on",
            // 탭 이름 — tmux는 기본으로 자기 제목(= attach 명령줄)을 내보내 탭 이름이 그걸로 굳는다(실측).
            // 안쪽 셸이 있는 폴더를 대신 전파해 자동 명명을 되살린다.
            "set-option -g set-titles on",
            "set-option -g set-titles-string '#{b:pane_current_path}'",
            // muxa가 이미 탭·도크 UI를 가지므로 tmux 하단 상태바는 중복이다(서비스 세션과 동일하게 끈다).
            "set-option -g status off",
            // Shift+Enter 등 수정자 조합 — tmux는 기본으로 extended keys를 끈다. 안 켜면 안쪽
            // TUI(Claude Code 등)가 kitty 프로토콜을 요청해도 Shift+Enter가 Enter로 뭉개진다.
            "set-option -s extended-keys on",
            // 바깥 터미널(ghostty, TERM=xterm-ghostty)이 extkeys를 지원한다고 알려야
            // tmux가 밖으로도 modifyOtherKeys를 요청해 조합을 구분해 받는다.
            "set-option -sa terminal-features 'xterm*:extkeys'",
            // 없으면 만들고 있으면 그대로 둔다(-A). 앱을 껐다 켜도 같은 이름이면 그 세션에 다시 붙는다.
            "new-session -d -A -s \(q) -c \(ShellQuote.single(cwd))\(envArgs)",
            // 서버 전역은 `on`이다(서비스가 죽은 뒤 exit code·로그를 읽어야 하므로). 터미널에 그대로 두면
            // 사용자가 `exit`를 쳐도 pane이 죽은 채 남아 탭이 안 닫히고 세션이 쌓인다.
            "set-option remain-on-exit off",
            // 붙는다. **exec를 쓰지 않는다**: detach하면 셸 프롬프트로 돌아와 탭이 살아남는다.
            "attach -t \(ShellQuote.single("=\(session)"))",
        ].joined(separator: " ';' ")
        return "\(ShellQuote.single(tmux)) -L \(ShellQuote.single(socket)) \(cmds)"
    }

    /// `startCommand` 결과를 ghostty `command` 필드로 **직접 exec**할 때의 래퍼(순수).
    ///
    /// `initial_input`(셸 stdin 주입)은 tty가 그 줄을 에코해, 탭이 열릴 때 tmux 명령이 한 번 번쩍인다
    /// (`clear`·`stty -echo`로도 못 막는다 — 셸이 줄을 읽기 전에 커널이 이미 에코한다). `command` 필드는
    /// ghostty가 프로세스를 직접 태워 에코 경로를 안 타므로 화면에 아무것도 안 찍힌다(번쩍임 제거).
    ///
    /// 두 가지를 지킨다 — 참조 구현 cmux(같은 GhosttyKit fork)의 `tmuxShellInvokedStartCommand`·
    /// `commandThenReturnLines`와 동일한 레시피다:
    ///  1. **`/bin/sh -c`로 감싼다** — ghostty는 command를 `exec -l <cmd>`로 태워 **단일 실행 파일**만
    ///     받는다(ghostty `src/termio/Exec.zig`). `;`로 이어진 tmux 서브명령 + attach는 복합 명령이라
    ///     감싸지 않으면 pane이 즉사한다.
    ///  2. **`exec -l $SHELL`로 로그인 셸을 남긴다** — attach가 detach되거나 끝나도 살아있는 셸이 남아
    ///     탭이 죽지 않는다(`initial_input` 방식의 "셸 유지"를 command 경로에서 재현). `$SHELL`
    ///     미설정이면 zsh로 폴백한다.
    ///
    /// `exec -l`은 POSIX sh 표준이 아니라 bash/zsh 빌트인 플래그다 — macOS `/bin/sh`가 bash라 동작한다
    /// (muxa는 macOS 전용). `/bin/sh`가 dash인 환경으로 이식하면 `-l`이 깨지므로 여기서 못 박아 둔다.
    static func execCommand(_ inner: String) -> String {
        // `exec -l "$SHELL"`의 큰따옴표는 sh가 확장한다(값에 공백이 있어도 안전). 바깥 작은따옴표는
        // ghostty의 word-split이 script를 인자 하나로 보게 하고, sh가 그 안을 셸 코드로 실행한다.
        let script = "\(inner); exec -l \"${SHELL:-/bin/zsh}\""
        return "/bin/sh -c \(ShellQuote.single(script))"
    }

    /// 이 탭이 **아직 tmux 세션에 붙어 있는가**(순수). 입력은 그 탭 pty의 포그라운드 프로세스 이름.
    ///
    /// `attach` 중이면 바깥 pty의 포그라운드는 **항상 tmux 클라이언트 하나**다 — 안쪽에서 도는
    /// 빌드·에이전트는 tmux가 따로 만든 pty에 살아서 바깥에선 안 보인다. 그래서 안쪽 내용에 흔들리지
    /// 않는 깨끗한 신호가 된다. 셸 이름이 보인다는 건 attach가 끝나 프롬프트로 돌아왔다는 뜻이다.
    ///
    /// `startCommand`가 `exec`를 안 쓰므로(탭을 살리려는 의도적 선택) 그 이탈은 **조용하다** —
    /// 화면은 멀쩡한 셸이고 탭은 `∞`를 단 채 남는다. 아무도 안 보면 아이콘이 계속 거짓말한다.
    ///
    /// - Parameter foregroundName: 못 읽었으면 nil. **모를 땐 붙어 있다고 본다**(보존적 판정) —
    ///   셸 스폰 직후엔 pid가 아직 0이라(TermView가 재시도한다) 그 구간을 끊김으로 다루면
    ///   탭을 만들자마자 `∞`가 떨어진다.
    static func isAttached(foregroundName: String?) -> Bool {
        guard let foregroundName else { return true }
        return normalized(foregroundName) == tmuxCommand
    }

    /// tmux 클라이언트의 프로세스 이름.
    private static let tmuxCommand = "tmux"

    /// 탭을 닫을 때 이 세션을 **죽일지, 백그라운드로 남길지**(순수).
    ///
    /// 그냥 죽이면 안전하지만 tmux의 값어치를 반쯤 버린다 — 30분 돌던 빌드가 있는 탭을 ⌘W로 잘못
    /// 누르면 그 자리에서 즉사한다. 반대로 무조건 남기면 유령 세션이 쌓인다.
    ///
    /// 그래서 **안에서 사용자 작업이 돌고 있을 때만 남긴다**. 셸만 있는 탭(= 프롬프트에서 놀고 있던 탭)은
    /// 남겨봐야 되찾을 것이 없으므로 조용히 죽인다.
    ///
    /// - Parameter foreground: 그 pane의 TTY에서 **포그라운드로 도는 프로세스 이름들**.
    ///
    /// tmux의 `#{pane_current_command}`를 쓰지 않는다. 그건 pane의 **맨 위 프로세스**만 보는데,
    /// 셸이 래퍼(`kiro-cli-term` 같은)로 감싸져 있으면 그 래퍼 이름만 돌려준다 — 안에서 빌드가 돌아도
    /// 영원히 "zsh"라고 답해 **detach 판정이 영영 안 걸린다**(실측으로 걸렸다). TTY의 포그라운드
    /// 프로세스 그룹을 직접 봐야 진짜로 뭐가 도는지 안다.
    static func shouldDetach(foreground: [String]) -> Bool {
        foreground.contains { !isShell($0) }
    }

    /// 되찾을 작업의 이름 — 목록에서 "무엇을 되찾는지"를 말해준다.
    ///
    /// 두 가지를 건너뛴다(둘 다 실측으로 걸렸다):
    ///  - **셸과 그 래퍼** — "zsh로 끝나지 않는 것"으로 고르면 `zsh (kiro-cli-term)`이 먼저 잡혀
    ///    정작 돌고 있는 빌드 대신 셸 이름이 뜬다.
    ///  - **버전 이름** — claude는 자기 자신을 버전 바이너리로 exec해서 트리에 `2.1.207` 같은
    ///    프로세스가 생긴다. 그걸 집으면 목록에 "2.1.207"이 떠서 **뭐가 도는지 알 수 없다**.
    static func workLabel(foreground: [String]) -> String? {
        for raw in foreground {
            let name = normalized(raw)
            guard !name.isEmpty, !shellNames.contains(name), !isVersionLike(name) else { continue }
            return name
        }
        return nil
    }

    /// `2.1.207`처럼 숫자와 점뿐인 이름 — 프로그램 이름이 아니라 버전이다.
    private static func isVersionLike(_ name: String) -> Bool {
        name.contains(".") && name.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// `/usr/bin/sleep` → `sleep`, `-zsh` → `zsh`, `zsh (wrapper)` → `zsh`
    private static func normalized(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("-") { name.removeFirst() }
        name = (name as NSString).lastPathComponent
        if let space = name.firstIndex(of: " ") { name = String(name[..<space]) }
        return name
    }

    /// 이 프로세스 이름이 "그냥 셸"인가 — detach 판정(shouldDetach)과 셸 pid 확정(§TermView.armProcessWatcher)이 공유한다.
    static func isShell(_ raw: String) -> Bool {
        let name = normalized(raw)
        return name.isEmpty || shellNames.contains(name)
    }

    /// "그냥 셸" 목록 — 이것만 돌고 있으면 되찾을 작업이 없다.
    private static let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "login"]

    /// 훅이 보낸 tabId를 **현재 살아있는 탭**으로 되짚는다(순수).
    ///
    /// tmux 세션 안 셸의 `MUXA_TAB_ID`는 **그 세션이 처음 만들어질 때의 tabId**다. 복원하면 tabId가
    /// 새로 발급되는데(Bonsplit `createTab`은 id를 지정받지 않는다) 세션 안 셸의 env는 그대로다.
    /// 그래서 훅은 옛 id로 신호를 보내고, 그대로 두면 muxa가 **어느 탭인지 못 찾아 알림이 사라진다**.
    ///
    /// 다행히 세션명이 다리가 된다: `muxa__<projectId>__term__<처음tabId>`. 현재 탭이 어떤 세션을
    /// 쓰는지는 muxa가 알고 있으므로(§tmuxSessions), 세션명에 박힌 옛 id로 현재 탭을 되찾을 수 있다.
    ///
    /// - Parameter sessionsByTab: 현재 tabId → 세션명.
    /// - Returns: 신호를 배달할 현재 tabId. 매칭이 없으면 nil(호출부가 원래 id를 그대로 쓴다).
    static func resolve(incomingTabId: String, sessionsByTab: [String: String]) -> String? {
        // 살아있는 탭 id면 그대로 — tmux를 안 쓰는 탭·같은 세션에서 새로 만든 탭의 정상 경로.
        if sessionsByTab[incomingTabId] != nil { return incomingTabId }
        for (currentTab, session) in sessionsByTab {
            if let parsed = parse(session), parsed.tabId == incomingTabId { return currentTab }
        }
        return nil
    }

    /// 정리해도 안전한 고아 터미널 세션 — 살아있는 탭이 참조하지 않는 것들.
    ///
    /// 보존(=건드리지 않음) 조건 — 하나라도 참이면 남긴다:
    ///  1) 터미널 세션이 아님 — 서비스 세션·남의 tmux 작업은 판정 대상이 아니다
    ///  2) **내가 모르는 프로젝트의 세션** — muxa 인스턴스는 여럿 떠 있을 수 있고(창 여러 개, 워크트리
    ///     빌드) 같은 tmux 소켓을 공유한다. 내 state에 없는 프로젝트의 세션은 남의 것이다. 이 가드가
    ///     없으면 인스턴스끼리 서로의 셸을 몰살한다(서비스 GC가 같은 이유로 배운 가드다).
    ///  3) 살아있는 탭이 참조함
    ///
    /// 판정 입력 `liveSessionNames`는 **스냅샷이 참조하는 세션명 전부**여야 한다. 열려 있는 탭만
    /// 넘기면 아직 안 연 프로젝트(lazy)의 세션이 고아로 몰려 죽는다.
    static func orphans(sessions: [String], liveSessionNames: Set<String>,
                        knownProjectIds: Set<String>) -> [String] {
        sessions.filter { session in
            guard let parsed = parse(session) else { return false }
            guard knownProjectIds.contains(parsed.projectId) else { return false }
            return !liveSessionNames.contains(session)
        }
    }
}
