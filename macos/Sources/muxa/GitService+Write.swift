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

    /// 파일 하나의 변경을 버린다(discard) — 체크 동선의 "거부" 반쪽(ARCHITECTURE 4.4).
    /// 성공 시 nil, 실패 시 사용자용 에러 메시지. 안전한 단계는 순수 계획(DiscardPlan)이 정하고 여기선 실행만.
    /// 리네임(R)은 원본·대상을 모두 처리해 데이터 손실을 막는다(DiscardPlan 참고).
    static func discard(_ change: GitFileChange, in dir: String) async -> String? {
        for step in DiscardPlan.steps(for: change) {
            switch step {
            case .git(let args):
                let r = await run(args, in: dir)
                if r.exitCode != 0 { return "변경 버리기 실패 (git \(args.first ?? "") exit \(r.exitCode))" }
            case .trash(let rel):
                if let err = trashItem(rel, in: dir) { return err }
            }
        }
        return nil
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

    /// hunk 패치를 워크트리에 거꾸로 적용(`git apply --reverse`, --cached 아님)해 그 hunk만 원복한다 = hunk 단위 버리기.
    /// 패치는 언스테이지 diff(워크트리 vs 인덱스)에서 뽑혔으므로, reverse 적용은 해당 hunk를 인덱스 상태로 되돌린다.
    /// 성공 시 nil, 실패 시 메시지. 스테이지·통 diff·untracked엔 부적합해 DiffView가 노출을 가드한다.
    static func applyReverse(patch: String, in dir: String) async -> String? {
        let r = await runWithStdin(["apply", "--reverse", "--whitespace=nowarn", "-"], stdin: patch, in: dir)
        guard r.exitCode != 0 else { return nil }
        let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "hunk 버리기 실패 (exit \(r.exitCode))" : msg
    }

    /// stdin으로 입력을 넣고 stderr까지 캡처하는 실행 변형(git apply 전용). 패치가 작아(파이프 버퍼 내)
    /// stdin을 먼저 다 쓰고 닫은 뒤 출력을 읽어 데드락을 피한다.
    static func runWithStdin(_ args: [String], stdin input: String, in dir: String) async -> FullResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = gitArgs(args)
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
