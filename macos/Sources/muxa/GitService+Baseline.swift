import Foundation

/// 기준선 검증 셸아웃 — 판정은 `BaselineResolve`(순수)에 위임하고 여기서는 사실만 모은다.
extension GitService {
    /// 기준선을 검증해 실제로 쓸 결정을 돌려준다. **diff를 여는 순간 1회**만 부른다 —
    /// 패널 refresh마다 돌리면 스크롤할 때마다 셸아웃 세 번이 된다.
    static func resolveBaseline(_ baseline: String?, in dir: String) async -> BaselineResolve.Decision {
        guard let baseline, !baseline.isEmpty else { return .degradeToHead }

        // `^{commit}`을 붙여야 "그 해시가 커밋으로 존재하는가"를 묻는다(태그·블롭이 아니라).
        let exists = await run(["cat-file", "-e", "\(baseline)^{commit}"], in: dir).exitCode == 0
        guard exists else { return BaselineResolve.decide(baseline: baseline, exists: false,
                                                          isAncestor: false, mergeBase: nil) }

        // exitCode 0 = 조상이다. 1 = 아니다. 그 밖(128 등)은 판정 불가 → 조상이 아닌 쪽으로 본다(안전).
        let isAncestor = await run(["merge-base", "--is-ancestor", baseline, "HEAD"], in: dir).exitCode == 0
        var mergeBase: String?
        if !isAncestor {
            let out = await run(["merge-base", baseline, "HEAD"], in: dir)
            let hash = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            mergeBase = (out.exitCode == 0 && !hash.isEmpty) ? hash : nil
        }
        return BaselineResolve.decide(baseline: baseline, exists: true,
                                      isAncestor: isAncestor, mergeBase: mergeBase)
    }

    /// 기준선 ↔ 워킹트리의 파일 하나 diff. 기준선을 먼저 검증하므로 **거짓 diff가 나오지 않는다**.
    /// 강등됐으면 그 사실도 함께 돌려준다 — 화면이 사유를 말할 수 있어야 한다.
    /// 이 경로가 속한 워크트리 루트. **`repoRoot`와 다르다** — 저건 링크 워크트리에서도
    /// 메인을 가리키지만, diff는 그 파일이 실제로 사는 워크트리에서 돌아야 한다.
    /// 경로가 저장소 밖이면 nil.
    static func worktreeRoot(containing path: String) async -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return nil }
        let r = await run(["rev-parse", "--show-toplevel"], in: parent)
        guard r.exitCode == 0 else { return nil }
        let root = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    static func baselineFileDiff(base: String, path: String,
                                 in dir: String) async -> (text: String,
                                                           decision: BaselineResolve.Decision) {
        let decision = await resolveBaseline(base, in: dir)
        let rev = BaselineResolve.revision(for: decision)

        // 추적 안 되는 파일은 어느 리비전에도 없다 — `--no-index`로 /dev/null 대비로 그린다
        // (기존 `worktreeDiff`가 untracked를 담는 방식과 같은 경로).
        let tracked = await run(["ls-files", "--error-unmatch", "--", path], in: dir).exitCode == 0
        if !tracked {
            let out = await run(["diff", "--no-color", "--no-index", "--", "/dev/null", path], in: dir)
            return (out.stdout, decision)
        }
        return (await run(["diff", "--no-color", rev, "--", path], in: dir).stdout, decision)
    }
}
