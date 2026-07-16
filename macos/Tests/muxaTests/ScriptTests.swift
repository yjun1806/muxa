import Foundation
import Testing
@testable import muxa

/// SCRIPT-TAB 1단계 순수 기반 — Script 모델 왕복·하위호환, 래퍼 문자열, script-exit 프레임 파싱.
///
/// 래퍼의 **인용(quoting)이 이 기능의 급소다**: 사용자 명령은 작은따옴표·공백·`$`를 품은 채
/// 두 겹 인용(`/bin/sh -c '…'` 안의 `"$SHELL" -l -c '…'`)을 뚫고 원형 그대로 도착해야 한다.
/// 문자열 핀만으로는 셸이 실제로 그렇게 읽는지 모른다 — 실전 검증은 진짜 /bin/sh로 돌린다.
struct ScriptTests {
    // MARK: Script 모델 — Codable 왕복·Project.scripts 하위호환

    @Test("Script는 Codable 왕복에서 그대로 돌아온다")
    func 스크립트왕복() throws {
        let s = Script(id: "s1", name: "build", command: "make build")
        let back = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test("scripts 필드가 없는 구 Project JSON은 nil로 디코드된다")
    func 구프로젝트하위호환() throws {
        // scripts는 물론 services·detached도 없던 옛 저장분 — 하위호환의 최저선.
        let json = Data(#"{"id":"p","name":"메인"}"#.utf8)
        let back = try JSONDecoder().decode(Project.self, from: json)
        #expect(back.scripts == nil)
    }

    @Test("Project.scripts는 왕복에서 그대로 돌아온다")
    func 프로젝트왕복() throws {
        let p = Project(id: "p", name: "메인",
                        scripts: [Script(id: "s1", name: "build", command: "make build")])
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back.scripts == p.scripts)
    }

    // MARK: 래퍼 문자열 핀 — 꼴이 바뀌면 여기서 먼저 깨진다

    @Test("래퍼 문자열 전체를 못 박는다 — sh -c 래핑·로그인 셸·exit 보고·조건부 exec")
    func 래퍼문자열핀() {
        let got = ScriptRunCommand.wrap(command: "make build", tabId: "TAB-1",
                                        notifyPath: "/opt/muxa/muxa-notify")
        let expected = #"/bin/sh -c '"${SHELL:-/bin/zsh}" -l -c '\''make build'\''; s=$?; MUXA_TAB_ID='\''TAB-1'\'' '\''/opt/muxa/muxa-notify'\'' script-exit --code "$s"; [ "$s" -eq 0 ] || exec -l "${SHELL:-/bin/zsh}"'"#
        #expect(got == expected)
    }

    // MARK: 래퍼 실전 검증 — 진짜 /bin/sh로 돌려 인용·exit 보고·조건부 exec를 증명한다

    @Test("작은따옴표·공백·$변수가 든 명령이 원형 그대로 안쪽 셸에 도착한다")
    func 인용실전() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("out")
        // 명령 자체에 작은따옴표("it's")·공백·$ 참조가 다 들어 있다 — $ 확장은 안쪽 셸의 몫이라
        // 래퍼가 미리 확장하거나 따옴표를 잃으면 결과 파일 내용이 어긋난다.
        let command = "printf '%s|%s' \"it's fine\" \"$MUXA_QUOTE_TEST\" > \"$MUXA_QUOTE_OUT\""
        let status = try runWrapped(command: command, tabId: "T", notifyPath: "/usr/bin/true",
                                    shell: "/bin/sh", home: dir,
                                    extraEnv: ["MUXA_QUOTE_TEST": "hello world",
                                               "MUXA_QUOTE_OUT": out.path])
        #expect(status == 0)
        #expect(try String(contentsOf: out, encoding: .utf8) == "it's fine|hello world")
    }

    @Test("실패하면 exit code가 보고되고 셸로 전환된다(exec를 탄다)")
    func 실패는exec() throws {
        let world = try makeWrapperWorld()
        defer { try? FileManager.default.removeItem(at: world.dir) }
        try runWrapped(command: "exit 7", tabId: "TAB-9",
                       notifyPath: world.notify, shell: world.shell, home: world.dir)
        #expect(try String(contentsOf: URL(fileURLWithPath: world.log), encoding: .utf8)
            == "TAB-9 script-exit --code 7")
        #expect(FileManager.default.fileExists(atPath: world.marker))
    }

    @Test("성공하면 code 0이 보고되고 exec를 안 탄다 — 프로세스가 죽어 탭이 닫히는 경로")
    func 성공은exec안탐() throws {
        let world = try makeWrapperWorld()
        defer { try? FileManager.default.removeItem(at: world.dir) }
        let status = try runWrapped(command: "exit 0", tabId: "TAB-9",
                                    notifyPath: world.notify, shell: world.shell, home: world.dir)
        #expect(status == 0)
        #expect(try String(contentsOf: URL(fileURLWithPath: world.log), encoding: .utf8)
            == "TAB-9 script-exit --code 0")
        #expect(!FileManager.default.fileExists(atPath: world.marker))
    }

    // MARK: parseScriptExit — 프레임 파싱(순수)

    @Test("정상 프레임을 파싱한다")
    func 프레임정상() {
        let msg = NotifyServer.parseScriptExit("script-exit\tTAB-1\t0\n")
        #expect(msg?.tabId == "TAB-1")
        #expect(msg?.exitCode == 0)
    }

    @Test("0이 아닌 코드도 그대로 읽는다")
    func 프레임비영코드() {
        #expect(NotifyServer.parseScriptExit("script-exit\tT\t127\n")?.exitCode == 127)
    }

    @Test("필드가 부족하면 nil")
    func 프레임필드부족() {
        #expect(NotifyServer.parseScriptExit("script-exit\tTAB-1") == nil)
        #expect(NotifyServer.parseScriptExit("script-exit\t") == nil)
    }

    @Test("코드가 숫자가 아니면 nil — 상태를 지어내지 않는다")
    func 프레임비숫자() {
        #expect(NotifyServer.parseScriptExit("script-exit\tT\tabc\n") == nil)
        #expect(NotifyServer.parseScriptExit("script-exit\tT\t1x\n") == nil)
        #expect(NotifyServer.parseScriptExit("script-exit\tT\t\n") == nil)
    }

    @Test("tabId가 비면 nil")
    func 프레임빈탭() {
        #expect(NotifyServer.parseScriptExit("script-exit\t\t0\n") == nil)
    }

    @Test("접두가 다르면 nil — 훅·줄 프로토콜을 삼키지 않는다")
    func 프레임접두() {
        #expect(NotifyServer.parseScriptExit("hook\tT\t0\n") == nil)
        #expect(NotifyServer.parseScriptExit("T\tdone\t제목\n") == nil)
    }

    @Test("첫 줄만 프레임이다 — 뒤에 노이즈가 붙어도 경계는 첫 개행 하나")
    func 프레임첫줄경계() {
        let msg = NotifyServer.parseScriptExit("script-exit\tT\t2\n노이즈\n")
        #expect(msg?.exitCode == 2)
    }

    // MARK: muxa-notify 와이어 계약 — 빌드된 실물 CLI가 script-exit 프레임을 소켓까지 실어 나른다

    /// 빌드 산출물 폴더의 muxa-notify — 테스트 번들(.xctest)과 같은 debug 디렉터리에 있다
    /// (Package.swift에서 muxaTests가 muxa-notify에 빌드 의존을 걸어 swift test가 함께 빌드한다).
    /// 번들은 `Bundle(for:)`로 찾는다 — swift-testing 실행에선 `Bundle.allBundles`에 .xctest가
    /// 안 잡힌다(실측). 그래도 못 찾는 환경(커스텀 빌드 레이아웃 등)이면 e2e는 건너뛴다(.enabled).
    private final class BundleAnchor {}
    private static let notifyBinary: URL? = {
        let url = Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("muxa-notify")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }()

    @Test("muxa-notify script-exit → NotifyServer.onScriptExit 엔드투엔드 — 방출 포맷이 파서와 실제로 맞물린다",
          .enabled(if: notifyBinary != nil))
    func 와이어계약() async throws {
        let bin = try #require(Self.notifyBinary)
        // 소켓용 **짧은** 전용 폴더 — makeTempDir(UUID 폴더명)은 sun_path 상한(104B)을 넘는다(실측 110).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mx-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sock = dir.appendingPathComponent("n.sock").path
        try #require(sock.utf8.count < 104) // 넘치면 이 환경에선 bind 불가 — 검증 불능

        let server = NotifyServer(socketPath: sock)
        defer { server.stop() }
        let (frames, cont) = AsyncStream.makeStream(of: ScriptExitMessage.self)
        server.onScriptExit = { cont.yield($0) }
        server.start()
        // bind는 백그라운드 큐에서 온다 — 소켓 파일이 생길 때까지 기다린다. CLI는 connect 실패 시
        // **조용히 접는**(fire-and-forget) 계약이라, 준비 전에 쏘면 프레임이 그냥 증발한다.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: sock) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: sock))
        try await Task.sleep(for: .milliseconds(50)) // bind→listen 사이 미시 창 회피

        // 실제 래퍼와 같은 호출 꼴: env로 소켓·탭을 받고, 인자로 exit code를 실어 보낸다.
        let p = Process()
        p.executableURL = bin
        p.arguments = ["script-exit", "--code", "42"]
        var env = ProcessInfo.processInfo.environment
        env["MUXA_SOCK"] = sock
        env["MUXA_TAB_ID"] = "TAB-E2E"
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0) // fire-and-forget 계약 — 어떤 경우에도 exit 0

        // 배달은 비동기다(서버의 EOF 읽기 → 메인 큐 dispatch) — 상한을 걸고 첫 프레임을 기다린다.
        let msg = await withTaskGroup(of: ScriptExitMessage?.self) { group in
            group.addTask { for await m in frames { return m }; return nil }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let received = try #require(msg, "5초 안에 script-exit 프레임이 배달되지 않았다")
        #expect(received.tabId == "TAB-E2E")
        #expect(received.exitCode == 42)
    }

    // MARK: 실전 검증용 부속 — 임시 폴더·가짜 notify/셸·래퍼 실행

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-script-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeExecutable(_ url: URL, _ content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// 래퍼의 관측 지점 일습: 가짜 notify(받은 인자·MUXA_TAB_ID를 log에 기록),
    /// 가짜 셸(인자 없이 불리면 = `exec -l "$SHELL"` — marker를 남김, 아니면 /bin/sh에 위임).
    private func makeWrapperWorld() throws
        -> (dir: URL, notify: String, shell: String, log: String, marker: String) {
        let dir = try makeTempDir()
        // notify 경로에 일부러 공백을 넣는다 — notifyPath 인용까지 같이 증명.
        let noteDir = dir.appendingPathComponent("note dir")
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("log").path
        let notify = noteDir.appendingPathComponent("fake-notify")
        try writeExecutable(notify, "#!/bin/sh\nprintf '%s %s' \"$MUXA_TAB_ID\" \"$*\" > '\(log)'\n")
        let marker = dir.appendingPathComponent("execd").path
        let shell = dir.appendingPathComponent("fake-shell")
        try writeExecutable(shell, """
        #!/bin/sh
        if [ $# -eq 0 ]; then : > '\(marker)'; exit 0; fi
        exec /bin/sh "$@"
        """)
        return (dir, notify.path, shell.path, log, marker)
    }

    /// wrap 결과(완성된 한 줄 명령)를 진짜 /bin/sh로 실행한다 — ghostty가 command 필드를
    /// 태우는 것과 등가인 최소 재현. SHELL은 파라미터로 갈아끼워 exec 경로를 관측한다.
    /// `home`(임시 폴더)으로 HOME·ZDOTDIR·ENV를 밀어 **밀폐**한다 — 래퍼가 로그인 셸(-l)을
    /// 타므로 그냥 두면 러너의 ~/.profile 등이 source돼 결과가 호스트 환경에 좌우된다.
    @discardableResult
    private func runWrapped(command: String, tabId: String, notifyPath: String,
                            shell: String, home: URL, extraEnv: [String: String] = [:]) throws -> Int32 {
        let wrapped = ScriptRunCommand.wrap(command: command, tabId: tabId, notifyPath: notifyPath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", wrapped]
        var env = ProcessInfo.processInfo.environment
        env["SHELL"] = shell
        env["HOME"] = home.path                                   // ~/.profile → 임시 폴더(없음 = 안 읽음)
        env["ZDOTDIR"] = home.path                                // zsh 계열 rc도 같은 곳으로
        env["ENV"] = home.appendingPathComponent(".shrc").path    // sh 대화형 rc — 없는 파일이라 조용히 건너뛴다
        for (key, value) in extraEnv { env[key] = value }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
