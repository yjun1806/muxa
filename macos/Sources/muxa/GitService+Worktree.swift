import Foundation

/// M4 — git worktree 자동화. 본체 GitService.run()은 stderr를 버려(diff/log 전용) 실패 원인을
///못 주므로, worktree add/remove는 stderr를 캡처하는 runResult로 실행해 UI에 오류를 보인다.
/// 모든 worktree 명령은 메인 워크트리(repo 루트)에서 실행한다 — 하위 워크트리 cwd면 add가 꼬인다.
extension GitService {
    struct FullResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// 워크트리 생성 결과 — 성공 시 만들어진 경로, 실패 시 사용자용 메시지.
    enum WorktreeAddResult {
        case ok(path: String)
        case failed(String)
    }

    /// stderr까지 캡처하는 실행 변형. 출력이 짧은 worktree 명령에만 쓴다(두 파이프 동시 읽기 데드락 회피).
    static func runResult(_ args: [String], in dir: String) async -> FullResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["git"] + args
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    cont.resume(returning: FullResult(
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self),
                        exitCode: proc.terminationStatus
                    ))
                } catch {
                    cont.resume(returning: FullResult(stdout: "", stderr: error.localizedDescription, exitCode: -1))
                }
            }
        }
    }

    /// 메인 워크트리(repo 루트) 경로. worktree add/list/remove·exclude의 기준.
    /// --git-common-dir로 공통 .git을 얻어 그 부모를 반환한다 — dir 자체가 링크 워크트리여도 메인을 가리킨다.
    /// (--show-toplevel은 '현재' 워크트리 루트라 링크 워크트리에선 메인이 아니어서 add가 엉뚱한 곳에 생긴다)
    static func repoRoot(in dir: String) async -> String? {
        let r = await run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: dir)
        guard r.exitCode == 0 else { return nil }
        let gitDir = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitDir.isEmpty else { return nil }
        let parent = (gitDir as NSString).deletingLastPathComponent // <main>/.git → <main>
        return parent.isEmpty ? nil : parent
    }

    /// 이 저장소의 워크트리 목록.
    static func worktreeList(in dir: String) async -> [GitWorktree] {
        guard let root = await repoRoot(in: dir) else { return [] }
        let r = await run(["worktree", "list", "--porcelain"], in: root)
        guard r.exitCode == 0 else { return [] }
        return GitWorktreeParser.parse(r.stdout)
    }

    /// 로컬 브랜치 이름들(생성 폼의 base 선택용).
    static func localBranches(in dir: String) async -> [String] {
        guard let root = await repoRoot(in: dir) else { return [] }
        let r = await run(["branch", "--format=%(refname:short)"], in: root)
        guard r.exitCode == 0 else { return [] }
        return r.stdout.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 워크트리 생성. 신규 브랜치면 `-b`로 base에서 분기, 기존 브랜치면 그 브랜치를 체크아웃.
    /// 경로는 repo 루트의 `.worktrees/<branch>` — info/exclude에 등록해 git status 오염을 막는다.
    static func worktreeAdd(branch: String, base: String, newBranch: Bool, in dir: String) async -> WorktreeAddResult {
        guard let root = await repoRoot(in: dir) else { return .failed("git 저장소가 아닙니다.") }
        let safe = branch.replacingOccurrences(of: "/", with: "-")
        let wtPath = (root as NSString).appendingPathComponent(".worktrees/\(safe)")
        if FileManager.default.fileExists(atPath: wtPath) {
            return .failed("워크트리 경로가 이미 있습니다: \(wtPath)\n(브랜치명 '/'→'-' 정규화 충돌일 수 있어요)")
        }

        var args = ["worktree", "add"]
        if newBranch {
            args += ["-b", branch, wtPath, base]
        } else {
            args += [wtPath, branch]
        }
        let r = await runResult(args, in: root)
        guard r.exitCode == 0 else {
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(msg.isEmpty ? "worktree add 실패 (exit \(r.exitCode))" : msg)
        }
        registerExclude(root: root)
        return .ok(path: wtPath)
    }

    /// 워크트리 제거(명시적 파괴 액션) — 성공 시 nil, 실패 시 메시지.
    static func worktreeRemove(_ path: String, in dir: String) async -> String? {
        guard let root = await repoRoot(in: dir) else { return "git 저장소가 아닙니다." }
        let r = await runResult(["worktree", "remove", path], in: root)
        guard r.exitCode == 0 else {
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "worktree remove 실패 (exit \(r.exitCode))" : msg
        }
        return nil
    }

    /// `.worktrees/`를 .git/info/exclude에 1회 등록 — 관리 폴더가 git status에 안 뜨게(cmux 패턴).
    private static func registerExclude(root: String) {
        let excludePath = (root as NSString).appendingPathComponent(".git/info/exclude")
        let existing = (try? String(contentsOfFile: excludePath, encoding: .utf8)) ?? ""
        if existing.contains(".worktrees/") { return }
        let prefix = (existing.isEmpty || existing.hasSuffix("\n")) ? "" : "\n"
        let updated = existing + prefix + ".worktrees/\n"
        try? updated.write(toFile: excludePath, atomically: true, encoding: .utf8)
    }
}
