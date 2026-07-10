import Foundation

/// 워크트리 하나 — `git worktree list --porcelain` 파싱 결과(값 타입).
struct GitWorktree: Identifiable {
    let path: String
    let branch: String?  // refs/heads/<b> → <b>. detached면 nil.
    let head: String     // 커밋 sha
    let isBare: Bool
    let isDetached: Bool

    var id: String { path }

    /// 표시용 이름 — 브랜치 없으면 detached sha 축약 또는 폴더명.
    var displayName: String {
        if let branch { return branch }
        if isDetached { return "(detached \(head.prefix(7)))" }
        return basename(path)
    }
}

/// porcelain 파서 — 순수 함수(부작용 없음). 레코드는 빈 줄로 구분된다.
enum GitWorktreeParser {
    static func parse(_ output: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        var path: String?
        var head = ""
        var branch: String?
        var bare = false
        var detached = false

        func flush() {
            if let path {
                result.append(GitWorktree(path: path, branch: branch, head: head, isBare: bare, isDetached: detached))
            }
            path = nil; head = ""; branch = nil; bare = false; detached = false
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "bare" {
                bare = true
            } else if line == "detached" {
                detached = true
            }
        }
        flush()
        return result
    }
}
