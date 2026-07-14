import Foundation

/// git 읽기 = `git` CLI 셸아웃(D5). libgit2 벤더링 부담 없이 status·diff·log를 그대로 얻는다.
/// 워크트리(M4)도 CLI라 일관. 대형 리포 성능은 FSEvents 부분갱신(M2)으로 보완.
enum GitService {
    struct Output {
        let stdout: String
        let exitCode: Int32
    }

    /// git 셸아웃 인자 조립(순수·SSOT) — 모든 실행 경로(run·runResult·runWithStdin)가 이걸 거친다.
    ///
    /// **`core.quotepath=false`가 항상 앞에 붙는다.** git 기본값은 true라 `status --porcelain`이
    /// 비ASCII 경로를 `"\355\225\234…"`(따옴표 + 8진 이스케이프)로 내보낸다. 그 문자열을 그대로
    /// 파싱해 담으면 `git add -- <path>`·`git diff -- <path>`·휴지통 이동이 전부 실제 파일과 안 맞아
    /// **한글 파일명이 Git 패널에서 통째로 안 먹는다**(사용자 머신의 기본값이 true다).
    static func gitArgs(_ args: [String]) -> [String] {
        ["git", "-c", "core.quotepath=false"] + args
    }

    /// 지정 디렉토리에서 git 명령을 백그라운드로 실행한다. stderr는 무시(nullDevice로 데드락 방지).
    static func run(_ args: [String], in dir: String) async -> Output {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = gitArgs(args)
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                // 에이전트가 같은 리포에서 git을 동시에 돌리는 중에도 인덱스 락을 건드리지 않는다 —
                // muxa의 상시 status/diff 폴링이 에이전트 커밋과 락 경합하는 것을 막는다(cmux 대조 ⑦).
                var env = ProcessInfo.processInfo.environment
                env["GIT_OPTIONAL_LOCKS"] = "0"
                proc.environment = env
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    cont.resume(returning: Output(stdout: String(decoding: data, as: UTF8.self), exitCode: proc.terminationStatus))
                } catch {
                    cont.resume(returning: Output(stdout: "", exitCode: -1))
                }
            }
        }
    }

    /// 현재 브랜치명만 가볍게 조회 — 상태바용. status(--porcelain 전체 스캔)보다 훨씬 싸다.
    /// git 저장소가 아니거나 detached HEAD면 nil.
    static func currentBranch(in dir: String) async -> String? {
        let result = await run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir)
        guard result.exitCode == 0 else { return nil }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty || branch == "HEAD" ? nil : branch
    }

    /// 워크트리 상태. git 저장소가 아니면 nil.
    static func status(in dir: String) async -> GitStatus? {
        let result = await run(["status", "--porcelain=v1", "--branch"], in: dir)
        guard result.exitCode == 0 else { return nil }
        return parseStatus(result.stdout)
    }

    /// 변경 파일 하나의 diff(unified). 상태에 맞는 명령을 고른다.
    static func fileDiff(_ change: GitFileChange, in dir: String) async -> String {
        if change.isUntracked {
            // 추적 안 됨 → 전체를 추가로 표시(exit 1이지만 stdout에 diff가 있다)
            return await run(["diff", "--no-color", "--no-index", "--", "/dev/null", change.path], in: dir).stdout
        }
        if change.worktree != " " {
            return await run(["diff", "--no-color", "--", change.path], in: dir).stdout // 언스테이지 변경
        }
        return await run(["diff", "--no-color", "--cached", "--", change.path], in: dir).stdout // 스테이지만
    }

    /// 워크트리 전체 통합 diff — 파일 하나씩이 아니라 변경 전체를 한 번에 훑는다.
    /// `git diff <base>`(추적 파일의 커밋+미커밋 변경)에, untracked 파일 각각을 /dev/null 대비
    /// diff로 합성해 붙인다(git diff <base>는 untracked를 안 보여줌). 순수 셸아웃·파싱.
    /// - base "HEAD": 현재 미커밋 전체. 세션 기준선을 주면 base..worktree(이번 세션 전체).
    static func worktreeDiff(base: String = "HEAD", in dir: String) async -> String {
        var parts: [String] = []
        let tracked = await run(["diff", "--no-color", base], in: dir).stdout
        if !tracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(tracked) }
        // untracked 파일은 status로 목록을 얻어 각각 /dev/null 대비 diff로 합성(fileDiff의 untracked 분기와 동일).
        if let status = await status(in: dir) {
            for change in status.changes where change.isUntracked {
                let d = await run(["diff", "--no-color", "--no-index", "--", "/dev/null", change.opPath], in: dir).stdout
                if !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(d) }
            }
        }
        return parts.joined(separator: "\n")
    }

    /// 최근 커밋 목록(히스토리). range를 주면 `<base>..HEAD` 같은 범위로 제한한다(세션 커밋용).
    static func log(in dir: String, limit: Int = 40, range: String? = nil) async -> [GitCommit] {
        // \u{1f}(unit separator)로 필드 구분 — 제목에 포함될 일이 없다.
        let format = "%H%x1f%h%x1f%s%x1f%an%x1f%ar"
        var args = ["log", "-n", "\(limit)", "--pretty=format:\(format)"]
        if let range { args.append(range) }
        let result = await run(args, in: dir)
        guard result.exitCode == 0 else { return [] }
        return parseLog(result.stdout)
    }

    /// log 출력(unit-separator 포맷) → 커밋 배열. 순수 파싱(테스트·재사용).
    static func parseLog(_ output: String) -> [GitCommit] {
        output.split(separator: "\n").compactMap { line in
            let f = String(line).components(separatedBy: "\u{1f}")
            guard f.count == 5 else { return nil }
            return GitCommit(hash: f[0], shortHash: f[1], subject: f[2], author: f[3], date: f[4])
        }
    }

    /// 현재 HEAD 커밋 해시(rev-parse). 세션 기준선 기록·리셋에 쓴다. git 저장소가 아니거나 커밋이 없으면 nil.
    static func headHash(in dir: String) async -> String? {
        let r = await run(["rev-parse", "HEAD"], in: dir)
        guard r.exitCode == 0 else { return nil }
        let h = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return h.isEmpty ? nil : h
    }

    /// 세션 기준선 이후 커밋들(`base..HEAD`) — "이번 세션에 에이전트가 커밋한 것". 각 커밋 diff는 commitDiff로 연다.
    /// 기준선이 유효하지 않거나(리베이스 등) 새 커밋이 없으면 빈 배열.
    static func sessionCommits(base: String, in dir: String) async -> [GitCommit] {
        await log(in: dir, limit: 200, range: "\(base)..HEAD")
    }

    /// 커밋 하나의 상세(메시지 + 변경 통계 + diff).
    static func commitDiff(_ hash: String, in dir: String) async -> String {
        await run(["show", "--no-color", "--stat", "-p", hash], in: dir).stdout
    }

    // MARK: 파싱 (porcelain v1 --branch)

    static func parseStatus(_ output: String) -> GitStatus {
        var branch = "?"
        var ahead = 0
        var behind = 0
        var changes: [GitFileChange] = []

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("## ") {
                var rest = String(line.dropFirst(3))
                if let bracket = rest.firstIndex(of: "[") {
                    let ab = String(rest[bracket...])
                    ahead = trailingInt(after: "ahead ", in: ab) ?? 0
                    behind = trailingInt(after: "behind ", in: ab) ?? 0
                    rest = String(rest[..<bracket]).trimmingCharacters(in: .whitespaces)
                }
                if let sep = rest.range(of: "...") {
                    branch = String(rest[..<sep.lowerBound])
                } else {
                    branch = rest.trimmingCharacters(in: .whitespaces)
                }
            } else if line.count >= 4 {
                // "XY path" — X=스테이지, Y=워크트리
                let x = line[line.startIndex]
                let y = line[line.index(line.startIndex, offsetBy: 1)]
                let path = String(line.dropFirst(3))
                changes.append(GitFileChange(path: path, index: x, worktree: y))
            }
        }
        return GitStatus(branch: branch, ahead: ahead, behind: behind, changes: changes)
    }

    /// "ahead 6" 같은 접두 뒤의 정수를 뽑는다.
    private static func trailingInt(after prefix: String, in text: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

/// 한 워크트리의 git 상태.
struct GitStatus {
    let branch: String
    let ahead: Int
    let behind: Int
    let changes: [GitFileChange]

    var isClean: Bool { changes.isEmpty }

    /// 인덱스에 올라간(스테이지된) 변경.
    var staged: [GitFileChange] { changes.filter { $0.isStaged } }
    /// 워크트리에 남은(언스테이지·추적안됨) 변경.
    var unstaged: [GitFileChange] { changes.filter { $0.worktree != " " } }
}

/// 커밋 하나(히스토리 항목).
struct GitCommit: Identifiable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let subject: String
    let author: String
    let date: String // 상대 시간("2 hours ago")
}

/// 변경된 파일 하나. index=스테이지 상태(X), worktree=언스테이지 상태(Y).
struct GitFileChange: Identifiable {
    var id: String { path }
    let path: String
    let index: Character
    let worktree: Character

    var isUntracked: Bool { index == "?" }
    var isStaged: Bool { index != " " && index != "?" }

    /// 스테이지된 리네임(porcelain v1은 인덱스 열에만 R을 표시). discard가 원본·대상 둘 다 처리해야 한다.
    var isRename: Bool { index == "R" }

    /// git add/restore 대상 경로 — 리네임("old -> new")은 새 경로를 쓴다.
    var opPath: String {
        if let r = path.range(of: " -> ") { return String(path[r.upperBound...]) }
        return path
    }

    /// 리네임 원본 경로("old -> new"의 old). 리네임이 아니면 path와 같다.
    var oldPath: String {
        if let r = path.range(of: " -> ") { return String(path[..<r.lowerBound]) }
        return path
    }

    /// 리네임 대상 경로(= opPath). 의미를 분명히 하려는 별칭.
    var newPath: String { opPath }

    /// 표시용 대표 상태 문자 — 스테이지 우선, 없으면 워크트리.
    var badge: Character {
        if isUntracked { return "?" }
        return index != " " ? index : worktree
    }
}
