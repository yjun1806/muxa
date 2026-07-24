import Foundation

/// Claude Code IDE 통합 락파일 — `~/.claude/ide/<port>.lock`. CLI가 이 파일을 읽어 ws 서버 포트·authToken을
/// 알아내 붙는다(터미널에 `CLAUDE_CODE_SSE_PORT`가 없는 외부 셸에서 `/ide`로 붙을 때의 discovery 경로).
///
/// 경계(파일 IO)와 순수(내용 조립·토큰 생성 분리)를 가른다. **파괴는 좁게**: 정리는 우리가 쓴 죽은
/// 락파일만 지운다(다른 IDE — 진짜 VS Code 등 — 의 락파일은 절대 안 건드린다). 의심되면 안 지운다.
enum IdeLockfile {
    /// 락파일 디렉터리 — `$CLAUDE_CONFIG_DIR/ide` 우선, 없으면 `~/.claude/ide`.
    static var directory: String {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? (SystemPaths.home as NSString).appendingPathComponent(".claude")
        return (base as NSString).appendingPathComponent("ide")
    }

    static func path(port: UInt16) -> String {
        (directory as NSString).appendingPathComponent("\(port).lock")
    }

    /// 락파일 JSON 내용(순수) — CLI가 읽는 필드 그대로. transport는 항상 "ws".
    static func content(pid: Int32, workspaceFolders: [String], ideName: String, authToken: String) -> [String: Any] {
        ["pid": Int(pid),
         "workspaceFolders": workspaceFolders,
         "ideName": ideName,
         "transport": "ws",
         "authToken": authToken]
    }

    /// 32자 소문자 hex(128bit) 토큰 — OS CSPRNG(SecRandomCopyBytes). ws 핸드셰이크 인증에 쓴다.
    static func newAuthToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 경계 — 파일 쓰기/삭제

    /// 락파일을 0600으로 쓴다(디렉터리는 0700). 실패하면 false(연결은 env 경로로도 되므로 치명적이지 않다).
    @discardableResult
    static func write(port: UInt16, content: [String: Any]) -> Bool {
        let dir = directory
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: content)
            let file = path(port: port)
            try data.write(to: URL(fileURLWithPath: file))
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
            return true
        } catch {
            return false
        }
    }

    static func remove(port: UInt16) {
        try? FileManager.default.removeItem(atPath: path(port: port))
    }

    /// **우리가 남긴 죽은 락파일만** 지운다(같은 ideName + pid 죽음). 다른 IDE(진짜 VS Code 등)의
    /// 락파일은 ideName이 달라 절대 안 건드린다 — 의심되면 안 지운다. 시작 시 1회 호출(고아 방지).
    /// `isAlive`는 테스트 주입(기본은 실제 프로세스 확인).
    static func cleanOrphans(ideName: String, isAlive: (Int32) -> Bool = defaultIsAlive) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for f in files where f.hasSuffix(".lock") {
            let file = (directory as NSString).appendingPathComponent(f)
            guard let data = fm.contents(atPath: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["ideName"] as? String == ideName,
                  let pid = obj["pid"] as? Int else { continue }
            if !isAlive(Int32(pid)) { try? fm.removeItem(atPath: file) }
        }
    }

    /// 프로세스 생존 확인 — `kill(pid, 0)`: 0=살아있음, EPERM=살아있으나 권한밖, ESRCH=죽음.
    static func defaultIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
