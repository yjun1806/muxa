import Foundation

/// 서비스 실행 백엔드 = `tmux` CLI 셸아웃(GitService와 같은 경계 패턴).
/// 부작용은 전부 여기, 판정은 전부 `ServiceSession`(순수)에 있다.
///
/// **전용 소켓(`-L muxa`)만 쓴다.** 사용자의 기본 tmux 서버와 완전히 분리되므로,
/// 우리가 세션을 죽여도 남의 작업에 닿지 않는다(고아 정리가 파괴적 동작이라 이 격리가 중요하다).
enum TmuxService {
    /// muxa 전용 tmux 소켓. 사용자의 기본 서버(`tmux`)와 섞이지 않는다.
    static let socket = "muxa"

    struct Output {
        let stdout: String
        let exitCode: Int32
    }

    /// tmux 설치 여부. 없으면 서비스 기능 전체를 숨긴다(gh 배지의 미설치 가드와 같은 방식).
    static let isAvailable: Bool = {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "tmux"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }()

    /// 전용 소켓에 tmux 명령을 실행한다. stderr는 무시(nullDevice로 데드락 방지 — GitService.run과 동일).
    static func run(_ args: [String]) async -> Output {
        guard isAvailable else { return Output(stdout: "", exitCode: -1) }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["tmux", "-L", socket] + args
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
    static func attachCommand(projectId: String, serviceId: String) -> String {
        "tmux -L \(socket) attach -t =\(ServiceSession.name(projectId: projectId, serviceId: serviceId))"
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
    /// 여기서는 죽이기만 한다. muxa 소유가 아닌 세션은 판정 단계에서 이미 걸러진다.
    /// - Returns: 실제로 정리한 세션 이름들.
    @discardableResult
    static func collectGarbage(liveServiceIds: Set<String>) async -> [String] {
        let orphans = ServiceSession.orphans(sessions: await sessions(), liveServiceIds: liveServiceIds)
        for session in orphans { await kill(session: session) }
        return orphans
    }
}
