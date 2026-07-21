import Foundation

/// `muxa-notify statusline` — Claude Code가 statusLine.command로 부르는 sink(A-1 경로).
///
/// Claude Code는 매 렌더마다 세션 JSON을 stdin으로 준다. 그 안의 `rate_limits`(claude가 코딩하며
/// 서버에서 관찰한 값)를 파일로 떨궈, muxa 앱이 사용량용 API를 **안 치고도** 읽게 한다 — 429 회피의 핵심.
///
/// 두 가지를 지킨다:
/// - **전역이라 조용하고 빨라야 한다.** statusLine은 settings.json 전역이라 muxa 밖 claude·타 앱 세션도
///   매 렌더마다 이걸 부른다. 어떤 실패도 렌더를 막지 않고, stdout은 오직 상태줄 텍스트만 낸다.
/// - **사용자 statusLine을 삼키지 않는다.** muxa가 밀어낸 원래 command가 `wrapped`에 있으면 같은 stdin을
///   먹여 실행하고 그 stdout을 그대로 통과시킨다(투명 프록시). 없으면 빈 줄(muxa UI가 사용량을 보여준다).
enum StatusLineSink {
    /// 모든 빌드가 공유하는 경로(앱 `MuxaSupportDir.sharedURL`과 동일 계산 — 빌드 무관 고정).
    /// 헬퍼는 앱 모듈을 import하지 못하므로 같은 규칙을 여기서 재현한다.
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("muxa-shared", isDirectory: true)
            .appendingPathComponent("statusline", isDirectory: true)
    }

    private static var latestURL: URL { directory.appendingPathComponent("latest.json") }
    /// 밀려난 사용자 statusLine command(plain text). 있으면 pass-through 대상.
    private static var wrappedURL: URL { directory.appendingPathComponent("wrapped") }

    /// stdin을 한 번 읽어 두 용도(추출·pass-through)에 재사용한다 — stdin은 한 번만 소비된다.
    static func run() {
        // 래핑된 사용자 command가 stdin을 다 안 읽고 끝나면 파이프 쓰기가 SIGPIPE로 프로세스를 즉사시킨다
        // (소켓 경로의 SO_NOSIGPIPE에 상응). 시그널을 무시해 EPIPE 에러로 받아 조용히 삼킨다 — statusLine
        // 렌더를 크래시로 막지 않게. 전역 statusLine이라 이 한 줄이 없으면 남의 스크립트에도 크래시가 번진다.
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        persist(input)
        passthrough(input)
    }

    /// `rate_limits`가 있을 때만 `{observedAt, rate_limits}`를 원자적으로 쓴다.
    /// 없으면(콜드스타트·첫 응답 전) **건드리지 않는다** — 신선했던 이전 값을 옛 응답으로 덮어 지우지 않게.
    /// session_id·cost 등 나머지 필드는 담지 않는다(필요한 것만, 프라이버시).
    private static func persist(_ input: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let rateLimits = root["rate_limits"] as? [String: Any], !rateLimits.isEmpty
        else { return }
        let record: [String: Any] = [
            "observedAt": Date().timeIntervalSince1970,
            "rate_limits": rateLimits,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent("latest.json.tmp")
        guard (try? data.write(to: temp, options: .atomic)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(latestURL, withItemAt: temp)
    }

    /// 밀려난 사용자 command가 있으면 같은 stdin을 먹여 실행하고 그 stdout을 그대로 낸다.
    /// 없으면 아무 출력도 하지 않는다. 실행 실패는 조용히 무시한다(렌더를 막지 않는다).
    private static func passthrough(_ input: Data) {
        guard let command = try? String(contentsOf: wrappedURL, encoding: .utf8),
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.standardOutput // 원래 statusLine 출력을 그대로 통과
        do {
            try process.run()
            // 자식이 stdin을 다 안 읽고 끝나면 EPIPE가 난다 — SIG_IGN(run) 덕에 시그널 대신 에러로 와서
            // try?로 삼켜진다. deprecated write(_:)는 못 잡는 예외를 던지므로 write(contentsOf:)를 쓴다.
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            // 사용자 command 실행 실패 — statusLine을 비운 채 조용히 넘어간다.
        }
    }
}
