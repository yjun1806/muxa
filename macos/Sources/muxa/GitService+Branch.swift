import Foundation

/// git 브랜치 전환 + 원격 동기화(pull/push). 실패 사유가 중요하므로 stderr를 캡처하는 runResult로 실행한다.
/// (checkout은 dirty면 git이 거부하고, pull/push는 원격 오류 메시지를 그대로 보여야 한다)
/// localBranches는 GitService+Worktree에 이미 있어 재사용한다.
extension GitService {
    /// 브랜치 전환(`git checkout`). 성공 시 nil, 실패 시 사용자용 에러 메시지.
    /// dirty 워크트리·미존재 브랜치 등은 git이 거부하고 stderr에 사유를 담는다.
    static func checkout(_ branch: String, in dir: String) async -> String? {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "브랜치명이 비었습니다" }
        return await syncMessage(["checkout", name], in: dir, fallback: "체크아웃 실패")
    }

    /// 원격에서 가져와 병합(`git pull`). 성공 시 nil, 실패 시 에러 메시지.
    static func pull(in dir: String) async -> String? {
        await syncMessage(["pull"], in: dir, fallback: "pull 실패")
    }

    /// 로컬 커밋을 원격에 올림(`git push` — 강제 아님). 성공 시 nil, 실패 시 에러 메시지.
    static func push(in dir: String) async -> String? {
        await syncMessage(["push"], in: dir, fallback: "push 실패")
    }

    /// 공통 실행 — 성공(exit 0) 시 nil, 실패 시 stderr(없으면 stdout, 그도 없으면 fallback)에서 사유를 뽑는다.
    private static func syncMessage(_ args: [String], in dir: String, fallback: String) async -> String? {
        let r = await runResult(args, in: dir)
        guard r.exitCode != 0 else { return nil }
        let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "\(fallback) (exit \(r.exitCode))" : out
    }
}
