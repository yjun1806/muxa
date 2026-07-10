import Foundation

/// git 쓰기(M4) = 스테이징·언스테이지·커밋. 읽기와 같은 CLI 셸아웃(GitService.run).
/// 결과는 exitCode로 성공 판정. FSEvents가 이후 상태를 자동 갱신한다.
extension GitService {
    /// 파일 하나를 스테이지(`git add`). 성공 시 true.
    @discardableResult
    static func stage(_ path: String, in dir: String) async -> Bool {
        await run(["add", "--", path], in: dir).exitCode == 0
    }

    /// 파일 하나를 언스테이지(`git restore --staged`). 성공 시 true.
    @discardableResult
    static func unstage(_ path: String, in dir: String) async -> Bool {
        await run(["restore", "--staged", "--", path], in: dir).exitCode == 0
    }

    /// 전부 스테이지(`git add -A` — 삭제·추적안됨 포함).
    @discardableResult
    static func stageAll(in dir: String) async -> Bool {
        await run(["add", "-A"], in: dir).exitCode == 0
    }

    /// 전부 언스테이지(`git reset` — 인덱스를 HEAD로).
    @discardableResult
    static func unstageAll(in dir: String) async -> Bool {
        await run(["reset", "-q"], in: dir).exitCode == 0
    }

    /// 파일 하나의 변경을 버린다(discard) — 체크 동선의 "거부" 반쪽(DESIGN 4.4).
    /// 성공 시 nil, 실패 시 사용자용 에러 메시지.
    /// - 추적 안 됨(untracked): 휴지통으로 이동(복구 가능 — git clean 대신).
    /// - 새로 스테이지된 파일(A): 언스테이지 후 휴지통으로 이동.
    /// - 그 외 추적 파일(수정·삭제 등): 인덱스·워크트리를 HEAD로 되돌림.
    static func discard(_ change: GitFileChange, in dir: String) async -> String? {
        // untracked → 휴지통(익스플로러 삭제와 동일, 복구 가능)
        if change.isUntracked {
            return trashItem(change.opPath, in: dir)
        }
        // 새로 add 된 파일 → 언스테이지 후 휴지통(HEAD에 없어 restore 불가)
        if change.index == "A" {
            _ = await run(["restore", "--staged", "--", change.opPath], in: dir)
            return trashItem(change.opPath, in: dir)
        }
        // 추적 파일 → 인덱스·워크트리를 마지막 커밋(HEAD) 상태로 되돌림
        let r = await run(["restore", "--staged", "--worktree", "--source=HEAD", "--", change.opPath], in: dir)
        guard r.exitCode != 0 else { return nil }
        return "변경 버리기 실패 (exit \(r.exitCode))"
    }

    /// 워크트리 파일을 휴지통으로 이동. 성공 시 nil, 실패 시 메시지. dir 기준 상대 경로를 절대 URL로 변환.
    private static func trashItem(_ relPath: String, in dir: String) -> String? {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(relPath)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return nil
        } catch {
            return "휴지통 이동 실패: \(error.localizedDescription)"
        }
    }

    /// 스테이지된 변경을 커밋. 성공 시 nil, 실패 시 사용자용 에러 메시지.
    static func commit(message: String, in dir: String) async -> String? {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return "커밋 메시지를 입력하세요" }
        let out = await run(["commit", "-m", msg], in: dir)
        guard out.exitCode != 0 else { return nil }
        // stderr는 nullDevice라 stdout의 마지막 비어있지 않은 줄을 힌트로(대개 실제 사유).
        let hint = out.stdout.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return hint.isEmpty ? "커밋 실패 (스테이지된 변경 없음?)" : hint
    }

    /// hunk 패치를 인덱스에 적용(`git apply --cached`, 패치는 stdin으로 전달). 성공 시 nil, 실패 시 메시지.
    /// DiffPatch로 만든 단일 hunk 패치를 넣어 hunk 단위 스테이지에 쓴다.
    static func applyCached(patch: String, in dir: String) async -> String? {
        let r = await runWithStdin(["apply", "--cached", "--whitespace=nowarn", "-"], stdin: patch, in: dir)
        guard r.exitCode != 0 else { return nil }
        let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "패치 적용 실패 (exit \(r.exitCode))" : msg
    }

    /// stdin으로 입력을 넣고 stderr까지 캡처하는 실행 변형(git apply 전용). 패치가 작아(파이프 버퍼 내)
    /// stdin을 먼저 다 쓰고 닫은 뒤 출력을 읽어 데드락을 피한다.
    static func runWithStdin(_ args: [String], stdin input: String, in dir: String) async -> FullResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["git"] + args
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardInput = inPipe
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    if let data = input.data(using: .utf8) {
                        try? inPipe.fileHandleForWriting.write(contentsOf: data)
                    }
                    try? inPipe.fileHandleForWriting.close()
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
}
