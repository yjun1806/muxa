import Foundation

/// git 읽기 = `git` CLI 셸아웃(D5). libgit2 벤더링 부담 없이 status·diff·log를 그대로 얻는다.
/// 워크트리(M4)도 CLI라 일관. 대형 리포 성능은 FSEvents 부분갱신(M2)으로 보완.
enum GitService {
    struct Output {
        let stdout: String
        let exitCode: Int32
    }

    /// 지정 디렉토리에서 git 명령을 백그라운드로 실행한다. stderr는 무시(nullDevice로 데드락 방지).
    static func run(_ args: [String], in dir: String) async -> Output {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["git"] + args
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
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

    /// 최근 커밋 목록(히스토리).
    static func log(in dir: String, limit: Int = 40) async -> [GitCommit] {
        // \u{1f}(unit separator)로 필드 구분 — 제목에 포함될 일이 없다.
        let format = "%H%x1f%h%x1f%s%x1f%an%x1f%ar"
        let result = await run(["log", "-n", "\(limit)", "--pretty=format:\(format)"], in: dir)
        guard result.exitCode == 0 else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line in
            let f = String(line).components(separatedBy: "\u{1f}")
            guard f.count == 5 else { return nil }
            return GitCommit(hash: f[0], shortHash: f[1], subject: f[2], author: f[3], date: f[4])
        }
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

    /// git add/restore 대상 경로 — 리네임("old -> new")은 새 경로를 쓴다.
    var opPath: String {
        if let r = path.range(of: " -> ") { return String(path[r.upperBound...]) }
        return path
    }

    /// 표시용 대표 상태 문자 — 스테이지 우선, 없으면 워크트리.
    var badge: Character {
        if isUntracked { return "?" }
        return index != " " ? index : worktree
    }
}
