import Foundation

/// 서비스 실행 백엔드 = `tmux` CLI 셸아웃(GitService와 같은 경계 패턴).
/// 부작용은 전부 여기, 판정은 전부 `ServiceSession`(순수)에 있다.
///
/// **전용 소켓(`-L muxa`)만 쓴다.** 사용자의 기본 tmux 서버와 완전히 분리되므로,
/// 우리가 세션을 죽여도 남의 작업에 닿지 않는다(고아 정리가 파괴적 동작이라 이 격리가 중요하다).
enum TmuxService {
    /// **서비스 전용** tmux 소켓 — 셋을 동시에 격리한다.
    ///
    ///  1. **사용자의 기본 tmux 서버**와 안 섞인다(전용 소켓).
    ///  2. **muxa의 다른 tmux 용도**와 안 섞인다. 세션 복원이 터미널을 tmux에 얹으면
    ///     (`muxa__<proj>__term__<uuid>`) 같은 소켓에서 서로가 "등록되지 않은 고아"로 보여
    ///     **서비스 청소가 남의 터미널을 죽인다.**
    ///  3. **다른 개발빌드**와 안 섞인다(`AppInfo.devKey`). 워크트리마다 muxa를 띄우면 각자의 state를
    ///     기준으로 고아를 판정하므로, 소켓이 같으면 서로의 dev 서버를 죽인다. 실제로 그렇게 터졌다.
    ///
    /// 정리가 **파괴적 동작**이라 "판정을 조심하기"보다 **대상을 물리적으로 분리**하는 쪽이 안전하다.
    static let socket: String = {
        guard let key = AppInfo.devKey else { return "muxa-services" }
        return "muxa-services-\(key)"
    }()

    struct Output {
        let stdout: String
        let exitCode: Int32
    }

    /// tmux 실행 파일의 **절대경로**. 없으면 nil(= 서비스 기능 전체를 숨긴다. gh 배지와 같은 미설치 가드).
    ///
    /// **PATH로 찾으면 안 된다.** `.app` 번들은 launchd가 띄우므로 로그인 셸의 PATH를 상속하지 않는다
    /// (`/usr/bin:/bin:/usr/sbin:/sbin` 정도만 있고 `/opt/homebrew/bin`이 없다). `env which tmux`로
    /// 찾으면 터미널에서 띄웠을 때만 동작하고, 정작 사용자가 Finder·Dock으로 여는 실사용 경로에서는
    /// 전부 실패해 기능이 통째로 사라진다.
    ///
    /// 그래서 (1) 사용자의 로그인 셸에게 직접 묻고, (2) 실패하면 알려진 설치 경로를 훑는다.
    /// 설치 직후 다시 찾을 수 있어야 하므로 `let`이 아니라 갱신 가능한 캐시로 둔다(refresh 참조).
    private(set) static var executable: String? = resolve("tmux",
                                                          fallbacks: ["/opt/homebrew/bin/tmux",
                                                                      "/usr/local/bin/tmux",
                                                                      "/usr/bin/tmux"])

    static var isAvailable: Bool { executable != nil }

    /// tmux를 다시 찾는다 — 사용자가 방금 설치했을 수 있다. 찾았으면 true.
    @discardableResult
    static func refresh() -> Bool {
        executable = resolve("tmux", fallbacks: ["/opt/homebrew/bin/tmux",
                                                 "/usr/local/bin/tmux",
                                                 "/usr/bin/tmux"])
        return isAvailable
    }

    /// Homebrew 실행 경로 — 설치 안내에서 "brew가 있는가"를 판단하는 데만 쓴다.
    static var brew: String? {
        resolve("brew", fallbacks: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    }

    /// 명령의 절대경로를 찾는다. 로그인 셸의 PATH를 먼저 묻고(사용자의 실제 환경), 실패하면
    /// 알려진 설치 경로를 훑는다.
    private static func resolve(_ command: String, fallbacks: [String]) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let path = capture(shell, ["-l", "-c", "command -v \(command)"]),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return fallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 프로세스를 실행해 stdout 첫 줄을 얻는다(경로 해석 전용 — 동기, 시작 시 1회).
    private static func capture(_ launchPath: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 전용 소켓에 tmux 명령을 실행한다. stderr는 무시(nullDevice로 데드락 방지 — GitService.run과 동일).
    ///
    /// `/usr/bin/env tmux`가 아니라 **해석해둔 절대경로로 직접 실행한다.** Finder·Dock에서 연 앱은
    /// launchd의 빈약한 PATH(`/usr/bin:/bin:/usr/sbin:/sbin`)를 받아 env가 tmux를 못 찾는다(`executable` 주석).
    static func run(_ args: [String]) async -> Output {
        guard let executable else { return Output(stdout: "", exitCode: -1) }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = ["-L", socket] + args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    cont.resume(returning: Output(stdout: String(decoding: data, as: UTF8.self),
                                                  exitCode: proc.terminationStatus))
                } catch {
                    cont.resume(returning: Output(stdout: "", exitCode: -1))
                }
            }
        }
    }

    // MARK: 기동

    /// 서비스를 시작한다(이미 있으면 아무것도 하지 않는다 — 멱등).
    ///
    /// 명령을 **로그인 셸로 감싸는 이유**: `.app` 번들로 띄운 muxa는 로그인 셸의 PATH를 상속하지 않아
    /// `pnpm`/`node`(homebrew·nvm 경로)를 못 찾는다. 감싸지 않으면 dev 서버가 command not found로 즉사한다.
    /// 인자를 배열로 넘기므로 명령에 따옴표가 섞여도 셸 인용이 필요 없다.
    static func start(_ service: Service, projectId: String, cwd: String) async {
        let session = ServiceSession.name(projectId: projectId, serviceId: service.id)
        guard await !exists(session) else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        await run(["new-session", "-d", "-s", session, "-c", cwd,
                   shell, "-l", "-c", service.command])
        await applyServerOptions()
    }

    /// 서버 전역 옵션. 세션이 생겨야 서버가 뜨므로 start 직후에 건다(멱등이라 매번 걸어도 무해).
    ///
    /// `remain-on-exit on`이 **필수**다. 이게 없으면 프로세스가 죽는 순간 pane이 증발해서
    /// exit code도 마지막 로그도 영영 못 읽는다 — 알림의 유일한 결정론적 신호가 사라진다.
    private static func applyServerOptions() async {
        await run(["set-option", "-g", "remain-on-exit", "on"])
        await run(["set-option", "-g", "status", "off"]) // 도크에 tmux 상태바가 이중으로 보이지 않게
    }

    static func exists(_ session: String) async -> Bool {
        await run(["has-session", "-t", "=\(session)"]).exitCode == 0
    }

    /// 도크가 펼쳐질 때 터미널에서 실행할 attach 명령. 접으면 서피스만 해제하면 되고,
    /// 프로세스는 tmux가 계속 붙잡고 있다(재부착 레이스를 안 밟는 이유).
    ///
    /// **타겟을 반드시 따옴표로 감싼다.** 이 명령만은 셸(zsh)을 거쳐 실행되는데, zsh에서 `=word`는
    /// "그 명령의 경로로 치환"하는 EQUALS 확장이다. 인용하지 않으면 세션 이름을 명령어로 착각해
    /// `zsh: muxa__... not found`로 죽는다. (`=`는 tmux에게 정확 매치를 요구하는 접두사이고,
    /// 인자 배열로 직접 실행하는 다른 명령들은 셸을 안 거쳐 이 문제가 없다.)
    /// 세션명은 우리가 만든 값(muxa__uuid__uuid)이라 작은따옴표 안에 안전하게 들어간다.
    static func attachCommand(projectId: String, serviceId: String) -> String {
        let tmux = ShellQuote.single(executable ?? "tmux")
        return "\(tmux) -L \(socket) attach -t '=\(ServiceSession.name(projectId: projectId, serviceId: serviceId))'"
    }

    /// **죽은** 서비스의 로그를 화면에 뿌리는 명령.
    ///
    /// 죽은 pane에 attach하면 tmux가 클라이언트 크기로 리사이즈하면서 화면 내용이 날아가고
    /// `Pane is dead`만 남는다 — 정작 왜 죽었는지(마지막 에러)를 못 본다. capture-pane은 그 내용을
    /// 온전히 갖고 있으므로, 죽은 서비스는 attach 대신 로그를 직접 출력한다.
    /// (`=<세션>:` 타겟과 zsh 인용 이유는 capture·attachCommand 주석 참조.)
    static func logCommand(projectId: String, serviceId: String, lines: Int = 200) -> String {
        let session = ServiceSession.name(projectId: projectId, serviceId: serviceId)
        let tmux = ShellQuote.single(executable ?? "tmux")
        return "\(tmux) -L \(socket) capture-pane -p -t '=\(session):' -S -\(lines)"
    }

    // MARK: 관측 — 접혀 있어도(서피스 렌더 없이) 읽는다

    /// 모든 서비스 세션의 상태. 서버가 없으면 빈 값(= 전부 missing).
    static func states() async -> [String: ServiceState] {
        let out = await run(["list-panes", "-a", "-F",
                             "#{session_name}|#{pane_dead}|#{pane_dead_status}"])
        guard out.exitCode == 0 else { return [:] }
        return ServiceSession.parsePanes(out.stdout)
    }

    /// 세션 이름 목록(고아 판정 입력).
    static func sessions() async -> [String] {
        let out = await run(["list-sessions", "-F", "#{session_name}"])
        guard out.exitCode == 0 else { return [] }
        return out.stdout.split(separator: "\n").map(String.init)
    }

    /// 로그 꼬리 — 렌더 없이 읽는다. 죽은 세션에서도 마지막 로그가 보존된다(사후 디버깅).
    ///
    /// 타겟이 `=<세션>:`인 이유: `capture-pane`은 pane 타겟을 받으므로 세션명에 `=`만 붙이면
    /// (`=<세션>`) pane으로 해석하려다 실패한다. 뒤의 `:`이 "그 세션의 현재 window"를 뜻해
    /// 정확 매치(`=`)와 pane 타겟을 동시에 만족한다.
    static func capture(projectId: String, serviceId: String, lines: Int = 100) async -> String {
        let session = ServiceSession.name(projectId: projectId, serviceId: serviceId)
        return await run(["capture-pane", "-p", "-t", "=\(session):", "-S", "-\(lines)"]).stdout
    }

    // MARK: 종료·정리

    static func kill(session: String) async {
        await run(["kill-session", "-t", "=\(session)"])
    }

    static func kill(projectId: String, serviceId: String) async {
        await kill(session: ServiceSession.name(projectId: projectId, serviceId: serviceId))
    }

    /// 좀비 정리 — 등록이 사라졌는데 살아남은 서비스 세션을 죽인다.
    ///
    /// tmux 세션은 muxa를 꺼도 살아남는다(그게 이 설계의 존재 이유다). 그 대가로, 등록이 지워진 뒤에도
    /// 프로세스가 남아 포트를 물고 CPU를 먹을 수 있다. 판정은 `ServiceSession.orphans`(순수)에 위임하고
    /// 여기서는 죽이기만 한다 — **우리가 확실히 아는 세션만** 대상이 된다(남의 tmux 작업도, 다른 muxa
    /// 인스턴스의 세션도 판정 단계에서 걸러진다).
    /// - Returns: 실제로 정리한 세션 이름들.
    @discardableResult
    static func collectGarbage(liveServiceIds: Set<String>, knownProjectIds: Set<String>) async -> [String] {
        let orphans = ServiceSession.orphans(sessions: await sessions(),
                                             liveServiceIds: liveServiceIds,
                                             knownProjectIds: knownProjectIds)
        for session in orphans { await kill(session: session) }
        return orphans
    }

    /// 그 세션의 마지막 화면 몇 줄 — **"어느 세션이었지"를 열기 전에 알려준다**.
    /// 명령 이름("claude")만으로는 여러 탭에서 같은 걸 돌렸을 때 구별이 안 된다. tmux가 화면을
    /// 통째로 갖고 있으므로 그걸 읽어 미리보기로 쓴다(저장하지 않는다 — 열 때마다 최신을 읽는다).
    static func tail(session: String, cwd: String? = nil, lines: Int = 3) async -> String {
        // **넉넉히 뜬 뒤 걸러낸다.** 딱 3줄만 뜨면 화면 맨 아래(= TUI 테두리·프롬프트)만 잡혀서
        // 알맹이가 한 줄도 안 남는다. 간추리기는 `ScreenPreview`(순수 함수)가 한다.
        let out = await run(["capture-pane", "-p", "-t", "=\(session):", "-S", "-60"])
        guard out.exitCode == 0 else { return "" }
        return ScreenPreview.summarize(out.stdout, cwd: cwd, home: SystemPaths.home, limit: lines)
    }

    /// 그 세션 pane의 TTY에서 **포그라운드로 도는 프로세스 이름들**. 탭을 닫을 때 "안에서 뭐가
    /// 돌고 있나"를 묻는 데 쓴다 — 셸뿐이면 죽이고, 작업이 있으면 남긴다(판정은 순수 함수).
    ///
    /// tmux의 `#{pane_current_command}`를 안 쓰는 이유: 그건 pane의 **맨 위 프로세스**만 본다.
    /// 셸이 래퍼로 감싸져 있으면(사용자 환경의 `kiro-cli-term` 등) 안에서 빌드가 돌아도 영원히
    /// "zsh"라 답해 판정이 영영 안 걸린다(실측으로 걸린 함정).
    static func paneForeground(session: String) async -> [String] {
        let raw = await run(["display-message", "-p", "-t", "=\(session):", "#{pane_pid}"])
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = pid_t(raw) else { return [] }
        // **프로세스 트리를 훑는다.** TTY의 포그라운드 그룹만 보면 부족하다 — 셸 래퍼(kiro-cli-term 등)가
        // 자체 pty를 만들어 실제 셸을 그 안에서 돌리면, pane의 tty에는 래퍼만 보이고 진짜 작업은
        // 그 아래 숨는다(실측). pane 프로세스의 모든 자손을 봐야 안에서 뭐가 도는지 알 수 있다.
        return AgentProcessDetector.descendantNames(of: root)
    }

    /// 고아 **터미널** 세션 정리(L3) — 닫힌 탭이 남긴 셸을 죽인다. 판정은 순수([[TerminalSession]]),
    /// 여기서는 죽이기만 한다. 서비스 세션과 남의 tmux 작업은 판정 단계에서 이미 걸러진다.
    @discardableResult
    static func collectTerminalGarbage(liveSessionNames: Set<String>,
                                       knownProjectIds: Set<String>) async -> [String] {
        let orphans = TerminalSession.orphans(sessions: await sessions(),
                                              liveSessionNames: liveSessionNames,
                                              knownProjectIds: knownProjectIds)
        for session in orphans { await kill(session: session) }
        return orphans
    }
}
