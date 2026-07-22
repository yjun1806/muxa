import Foundation

/// Claude Code가 `~/.claude/projects/`에 남기는 세션 인덱스를 읽어, cwd에 대한 재개 명령을 만든다. (제로설정 재개, cmux식)
///
/// Claude는 프로젝트(cwd)마다 `~/.claude/projects/<인코딩된-cwd>/<세션UUID>.jsonl`에 대화를 기록하고,
/// 그 디렉터리에서 가장 최근에 수정된 `.jsonl`이 현재(마지막) 세션이다. muxa는 훅 없이 이 인덱스를 직접 읽어
/// `claude --resume <세션UUID>`를 스스로 구성한다 — 명령이 muxa 자가구성(임의 문자열 아님)이라 복원 시
/// 이건 **추측**이다(mtime이 가장 최근인 파일). 훅이 알려준 사실이 아니므로 자동 실행하지 않는다([[ResumeBinding]] source=.scan).
///
/// 부작용(디렉터리 읽기)은 이 경계 타입에 격리하고, 인코딩 규칙(`encodeProjectDir`)·세션 id 검증
/// (`isSafeSessionId`)은 순수 함수로 분리해 테스트 가능하게 둔다.
enum ClaudeSessionIndex {
    /// Claude Code가 cwd를 `~/.claude/projects/` 아래 폴더 이름으로 바꾸는 규칙을 재현한다:
    /// 경로의 `/`와 `.`을 전부 `-`로 치환한다. Claude의 온디스크 규약이라, 그 폴더를 찾으려면
    /// 같은 방식으로 인코딩해야 한다. (예: `/Users/me/app` → `-Users-me-app`)
    static func encodeProjectDir(_ cwd: String) -> String {
        String(cwd.map { ($0 == "/" || $0 == ".") ? "-" : $0 })
    }

    /// 세션 id가 안전한지 — **UUID 꼴만** 통과시킨다. Claude가 실제로 쓰는 형식이고, 이 id는
    /// `claude --resume <id>`로 조립돼 **셸에 커밋된다**(auto면 사용자 확인 없이).
    ///
    /// 종전엔 `[A-Za-z0-9._-]`만 걸렀는데, 그 규칙은 셸 메타문자는 막아도 **플래그 모양 문자열은 통과시킨다** —
    /// `--dangerously-skip-permissions`에는 금지 문자가 하나도 없다. session_id는 소켓으로 들어오는 외부
    /// 입력이라(같은 uid의 아무 프로세스나 실을 수 있다) 그걸 그대로 인자 자리에 넣으면 플래그 주입이 된다.
    /// 형식을 아는 값은 형식으로 검증한다 — 문자 블랙리스트가 아니라 화이트리스트로.
    static func isSafeSessionId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    /// 기본 Claude 세션 루트 — `~/.claude/projects`.
    static let defaultProjectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    /// `<projectsRoot>/<인코딩된-cwd>/`에서 가장 최근 수정된 비어있지 않은 `.jsonl`의 stem(=세션 id). 없으면 nil.
    /// 세션이 도는 동안엔 그 세션 파일이 계속 쓰이므로 "가장 최근 = 현재 세션"이 성립한다.
    static func latestSessionId(forCwd cwd: String, projectsRoot: URL = defaultProjectsRoot) -> String? {
        let dir = projectsRoot.appendingPathComponent(encodeProjectDir(cwd), isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }

        let sessions = items.filter { $0.pathExtension == "jsonl" }
        let newest = sessions
            .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 > 0 } ?? false }
            .max { a, b in modified(a) < modified(b) }
        guard let id = newest?.deletingPathExtension().lastPathComponent, isSafeSessionId(id) else { return nil }
        return id
    }

    /// cwd의 최신 세션 transcript(JSONL) 경로. 백그라운드 claude 세션의 미리보기를
    /// **화면이 아니라 대화 기록**에서 뽑는 데 쓴다 — claude는 TUI라 화면 마지막 줄은 입력 상자(HUD)뿐이다.
    static func latestTranscriptPath(forCwd cwd: String, projectsRoot: URL = defaultProjectsRoot) -> String? {
        guard let id = latestSessionId(forCwd: cwd, projectsRoot: projectsRoot) else { return nil }
        return projectsRoot
            .appendingPathComponent(encodeProjectDir(cwd), isDirectory: true)
            .appendingPathComponent("\(id).jsonl").path
    }

    /// cwd에 Claude 세션이 있으면 **추측** 재개 바인딩(.scan)을 만든다. 없으면 nil.
    /// 훅 바인딩이 없을 때의 폴백이다 — 배너로 사용자 확인을 받은 뒤에만 실행된다.
    static func resumeBinding(forCwd cwd: String, projectsRoot: URL = defaultProjectsRoot) -> ResumeBinding? {
        guard let id = latestSessionId(forCwd: cwd, projectsRoot: projectsRoot) else { return nil }
        return ResumeBinding(command: "claude --resume \(id)", agentLabel: "claude", cwd: cwd, source: .scan)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
