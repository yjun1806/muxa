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
}
