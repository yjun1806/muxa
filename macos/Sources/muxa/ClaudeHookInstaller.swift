import Foundation

/// 훅 설치 상태 — UI가 이 값 하나로 표시·행동을 정한다.
///
/// `installed`와 `verified`를 나누는 게 핵심이다. settings.json에 썼다는 것과 훅이 **실제로 발화한다**는
/// 것은 다르다(경로 오타·권한·사용자가 나중에 지움·Claude 버전 차이). 첫 훅 신호가 도착하기 전까지는
/// 정직하게 "미검증"이라고 말한다 — 안 되는 걸 된다고 표시하는 게 최악이다.
enum HookInstallState: Equatable {
    /// settings.json에 muxa 훅이 없다.
    case notInstalled
    /// 설치는 됐지만 아직 훅 신호를 한 번도 못 받았다.
    case installed
    /// 설치됐고 실제 훅 신호가 도착했다.
    case verified
    /// 설치 시도가 실패했다(권한·JSON 파손 등).
    case failed(String)

    var label: String {
        switch self {
        case .notInstalled: return "훅 미설치 — 추정으로 동작"
        case .installed: return "훅 설치됨 — 신호 대기 중"
        case .verified: return "훅 동작 중"
        case .failed(let reason): return "훅 설치 실패 — \(reason)"
        }
    }
}

/// `~/.claude/settings.json`에 muxa 훅을 설치/제거하는 **경계** 타입(파일 IO).
/// 병합 규칙(무엇을 쓰는가)은 전부 순수 함수 `ClaudeHookSettings`에 있다 — 여기는 안전한 쓰기만 책임진다.
///
/// 안전 규칙:
/// - **쓰기 전에 백업**(`settings.json.muxa-backup`). 되돌릴 수 없는 파괴는 만들지 않는다.
/// - **원자적 교체**(임시 파일 → replaceItem). 중간에 죽어도 반쪽 JSON이 남지 않는다.
/// - **파싱 실패면 아무것도 안 쓴다.** 사용자가 손으로 편집하다 깨뜨린 파일을 우리가 덮어써 지우면 안 된다.
enum ClaudeHookInstaller {
    enum InstallError: LocalizedError {
        case malformedSettings
        case missingBinary
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .malformedSettings: return "settings.json을 읽을 수 없다(JSON 파손)"
            case .missingBinary: return "muxa-notify 실행 파일을 찾을 수 없다"
            case .writeFailed(let reason): return reason
            }
        }
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// 훅이 호출할 안정 경로. **앱 번들 안 경로를 쓰면 안 된다** — 앱을 옮기거나 지우면 사용자의
    /// settings.json에 죽은 경로가 남는다. Application Support는 앱 위치와 무관하게 고정이다.
    static var executableURL: URL {
        MuxaSupportDir.subdirectory("bin").appendingPathComponent("muxa-notify")
    }

    /// 현재 설치 상태(신호 수신 여부는 호출자가 안다 — 여긴 파일만 본다).
    static func installState() -> HookInstallState {
        guard let root = readSettings() else { return .notInstalled }
        return ClaudeHookSettings.isInstalled(in: root, executable: executableURL.path) ? .installed : .notInstalled
    }

    /// statusLine sink를 부르는 command(A-1 경로). 훅과 같은 헬퍼·같은 존재 가드·같은 인용을 쓴다 —
    /// muxa를 지우면 이 command가 settings.json에 남으므로 `if [ -x … ]`로 감싸 없으면 조용히 통과시킨다.
    static var statusLineCommand: String {
        let quoted = ClaudeHookSettings.shellQuoted(executableURL.path)
        return "if [ -x \(quoted) ]; then \(quoted) statusline; fi"
    }

    /// 밀려난 사용자 statusLine command를 sink가 pass-through하도록 저장하는 파일(공유 경로).
    static var wrappedStatusLineURL: URL {
        MuxaSupportDir.sharedURL
            .appendingPathComponent("statusline", isDirectory: true)
            .appendingPathComponent("wrapped")
    }

    /// muxa 훅 + statusLine sink를 설치한다(멱등 — 여러 번 호출해도 불어나지 않는다).
    /// 사용자 statusLine이 있으면 그 command를 래핑 파일에 보존해 sink가 통과시킨다.
    static func install() throws {
        try stageBinary()
        let root = try requireSettings()
        do {
            let withHooks = try ClaudeHookSettings.merged(into: root, executable: executableURL.path)
            let (withStatusLine, displaced) = try ClaudeStatusLineSettings.merged(
                into: withHooks, command: statusLineCommand)
            if let displaced { try saveWrappedStatusLine(displaced) }
            try write(withStatusLine)
        } catch is ClaudeHookSettings.UnexpectedShape {
            throw InstallError.malformedSettings
        } catch is ClaudeStatusLineSettings.UnexpectedShape {
            throw InstallError.malformedSettings
        }
    }

    /// muxa 훅·statusLine만 제거한다(사용자 것은 남긴다). 밀려났던 사용자 statusLine이 래핑 파일에
    /// 있으면 되살린다 — muxa를 걷어내도 사용자의 원래 상태줄이 유실되지 않게.
    static func uninstall() throws {
        let root = try requireSettings()
        do {
            var next = try ClaudeHookSettings.removed(from: root)
            next = try ClaudeStatusLineSettings.removed(from: next)
            if let wrapped = restoreWrappedStatusLine() {
                (next, _) = try ClaudeStatusLineSettings.merged(into: next, command: wrapped)
            }
            try write(next)
        } catch is ClaudeHookSettings.UnexpectedShape {
            throw InstallError.malformedSettings
        } catch is ClaudeStatusLineSettings.UnexpectedShape {
            throw InstallError.malformedSettings
        }
    }

    /// 밀려난 사용자 statusLine command를 공유 래핑 파일에 저장한다(sink가 읽어 pass-through).
    private static func saveWrappedStatusLine(_ command: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: wrappedStatusLineURL.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try command.write(to: wrappedStatusLineURL, atomically: true, encoding: .utf8)
    }

    /// 래핑 파일에 저장된 사용자 command(있으면). 복원 후 파일은 지운다 — 재설치 시 유령이 남지 않게.
    private static func restoreWrappedStatusLine() -> String? {
        guard let command = try? String(contentsOf: wrappedStatusLineURL, encoding: .utf8),
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        try? FileManager.default.removeItem(at: wrappedStatusLineURL)
        return command
    }

    // MARK: 내부 — 안전한 IO

    /// 앱 옆의 muxa-notify를 Application Support의 안정 경로로 복사한다(매번 덮어써 버전 스큐를 막는다).
    /// 앱을 업데이트하면 CLI도 같이 갱신돼야 와이어 프로토콜이 어긋나지 않는다.
    private static func stageBinary() throws {
        guard let source = bundledBinaryURL() else { throw InstallError.missingBinary }
        let destination = executableURL
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            throw InstallError.writeFailed("muxa-notify 설치 실패: \(error.localizedDescription)")
        }
    }

    /// 실행 파일 옆의 muxa-notify(.app 번들이든 bare 빌드든 같은 디렉터리에 있다).
    /// 스크립트 래퍼(TerminalStore)도 이 경로를 절대경로로 박아 쓴다 — .app은 로그인 PATH를
    /// 상속하지 않으므로 PATH 의존은 금지고, 훅 미설치 사용자도 이 경로는 항상 있다.
    /// (훅과 달리 래퍼는 디스크에 영속되지 않아 "번들 안 경로 금지" 원칙(§executableURL)의 예외다.)
    static func bundledBinaryURL() -> URL? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let candidate = exe.deletingLastPathComponent().appendingPathComponent("muxa-notify")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// settings.json을 읽는다. 파일이 없으면 빈 설정(신규 생성), **깨졌으면 에러**(덮어쓰지 않는다).
    private static func requireSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let root = readSettings() else { throw InstallError.malformedSettings }
        return root
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return root
    }

    /// 백업 → 임시 파일 → 원자적 교체. 중간에 죽어도 반쪽 JSON이 남지 않는다.
    ///
    /// **심링크를 따라간다.** settings.json을 dotfiles 리포로 심링크해 쓰는 사람이 많은데,
    /// 링크 경로에 그대로 쓰면 `replaceItemAt`이 **심링크를 일반 파일로 갈아치워** dotfiles 연결이
    /// 조용히 끊긴다. 백업도 링크를 복사하면 원본을 가리키는 링크가 되어 롤백 수단이 되지 못한다.
    private static func write(_ root: [String: Any]) throws {
        let fm = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let current = try? Data(contentsOf: target) {
                // 백업은 **내용 복사**다(copyItem은 심링크를 심링크로 복사한다).
                // 이미 있으면 덮지 않는다 — 두 번째 설치가 첫 백업을 "muxa 훅이 박힌 버전"으로
                // 오염시키면 설치 이전 상태로 되돌릴 방법이 사라진다.
                let backup = target.appendingPathExtension("muxa-backup")
                if !fm.fileExists(atPath: backup.path) { try current.write(to: backup) }
            }
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            let temp = target.appendingPathExtension("muxa-tmp")
            try data.write(to: temp, options: .atomic)
            _ = try fm.replaceItemAt(target, withItemAt: temp)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
    }
}
