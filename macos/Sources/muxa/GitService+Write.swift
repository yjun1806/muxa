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
}
