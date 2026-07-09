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

    /// 파일 하나의 diff(unified). 언스테이지 우선, 없으면 스테이지된 것.
    static func diff(path: String, in dir: String, staged: Bool) async -> String {
        let args = staged ? ["diff", "--cached", "--", path] : ["diff", "--", path]
        return await run(args, in: dir).stdout
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
}

/// 변경된 파일 하나. index=스테이지 상태(X), worktree=언스테이지 상태(Y).
struct GitFileChange: Identifiable {
    var id: String { path }
    let path: String
    let index: Character
    let worktree: Character

    var isUntracked: Bool { index == "?" }
    var isStaged: Bool { index != " " && index != "?" }

    /// 표시용 대표 상태 문자 — 스테이지 우선, 없으면 워크트리.
    var badge: Character {
        if isUntracked { return "?" }
        return index != " " ? index : worktree
    }
}
