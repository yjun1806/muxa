import Foundation

/// Claude Code가 `~/.claude/projects/`에 남기는 세션 인덱스를 읽어, cwd에 대한 재개 명령을 만든다. (제로설정 재개, cmux식)
///
/// Claude는 프로젝트(cwd)마다 `~/.claude/projects/<인코딩된-cwd>/<세션UUID>.jsonl`에 대화를 기록하고,
/// 그 디렉터리에서 가장 최근에 수정된 `.jsonl`이 현재(마지막) 세션이다. muxa는 훅 없이 이 인덱스를 직접 읽어
/// `claude --resume <세션UUID>`를 스스로 구성한다 — 명령이 muxa 자가구성(임의 문자열 아님)이라 복원 시
/// 자동 실행이 안전하다([[ResumeBinding]]의 trusted).
///
/// 부작용(디렉터리 읽기)은 이 경계 타입에 격리하고, 인코딩 규칙(`encodeProjectDir`)·세션 id 검증
/// (`isSafeSessionId`)은 순수 함수로 분리해 테스트 가능하게 둔다.
enum ClaudeSessionIndex {
    /// Claude가 cwd로 프로젝트 디렉터리 이름을 만드는 규칙: `/`와 `.`를 모두 `-`로 바꾼다.
    /// (예: `/Users/x/repo/.claude` → `-Users-x-repo--claude`.) cmux `encodeClaudeProjectDir`로 검증된 규칙.
    static func encodeProjectDir(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// 세션 id가 파일명·셸에 안전한지 — 실제 파일명(UUID)에서 왔지만 방어적으로 검증한다(경로 이스케이프·주입 차단).
    static func isSafeSessionId(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".."
            && id.range(of: "[^A-Za-z0-9._-]", options: .regularExpression) == nil
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

    /// cwd에 Claude 세션이 있으면 신뢰(trusted) 재개 바인딩을 만든다. 없으면 nil.
    static func resumeBinding(forCwd cwd: String, projectsRoot: URL = defaultProjectsRoot) -> ResumeBinding? {
        guard let id = latestSessionId(forCwd: cwd, projectsRoot: projectsRoot) else { return nil }
        return ResumeBinding(command: "claude --resume \(id)", agentLabel: "claude", cwd: cwd, trusted: true)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
