import Foundation

/// 탭 기준선 커밋을 지금도 diff의 기준으로 쓸 수 있는가 — **판정만**(순수). 셸아웃은 경계가 한다.
///
/// 이 판정이 필요한 이유는 실패가 아니라 **오도**다. `rebase`·`reset --hard`·브랜치 전환 뒤에도
/// 기준선 객체는 reflog가 붙잡고 있어 살아 있는데, 그게 더는 `HEAD`의 조상이 아니다.
/// 그 상태로 `git diff <base>`를 돌리면 **성공하면서** 남의 커밋 차이까지 섞인 diff를 낸다 —
/// 조용히 틀린 화면은 에러 화면보다 나쁘다.
///
/// (`git mv` + 커밋은 히스토리를 앞으로만 쌓으므로 조상 관계를 깨지 않는다 — waymark 흐름은 안전하다.)
enum BaselineResolve {
    enum Decision: Equatable {
        /// 그대로 쓴다 — 기준선이 살아 있고 `HEAD`의 조상이다.
        case use(String)
        /// 조상이 아니게 됐다 → **분기점**으로 강등. rebase 전 갈라진 지점이라
        /// 사용자 기대("내 작업 이후")에 가장 가깝다.
        case degradeToMergeBase(String)
        /// 기준선을 못 쓴다(없거나 객체가 사라졌거나 공통 조상도 없다) → `HEAD` 기준으로 강등.
        /// 화면은 그 사실을 말해야 한다 — 조용히 다른 걸 보여주지 않는다.
        case degradeToHead
    }

    /// - Parameters:
    ///   - baseline: 얼려둔 기준선 해시. 아직 없으면 nil.
    ///   - exists: 그 객체가 저장소에 남아 있는가 (`git cat-file -e <base>^{commit}`).
    ///   - isAncestor: `HEAD`의 조상인가 (`git merge-base --is-ancestor`).
    ///   - mergeBase: 조상이 아닐 때의 공통 조상 (`git merge-base`). 없으면 nil.
    static func decide(baseline: String?, exists: Bool,
                       isAncestor: Bool, mergeBase: String?) -> Decision {
        guard let baseline, !baseline.isEmpty else { return .degradeToHead }
        guard exists else { return .degradeToHead }          // gc가 지웠다
        if isAncestor { return .use(baseline) }
        // 조상이 아니다 — 여기서 그대로 쓰면 거짓 diff가 된다.
        guard let mergeBase, !mergeBase.isEmpty else { return .degradeToHead }
        return .degradeToMergeBase(mergeBase)
    }

    /// diff에 실제로 넘길 리비전. `HEAD` 강등이면 nil이 아니라 `"HEAD"`를 쓴다
    /// (미커밋 변경만 보여주는 기존 동작과 같아진다).
    static func revision(for decision: Decision) -> String {
        switch decision {
        case .use(let hash): return hash
        case .degradeToMergeBase(let hash): return hash
        case .degradeToHead: return "HEAD"
        }
    }

    /// 사용자에게 말할 사유. 정상이면 nil — **모르면 침묵하되, 강등은 말한다**.
    static func notice(for decision: Decision) -> String? {
        switch decision {
        case .use: return nil
        case .degradeToMergeBase: return "기준선이 히스토리에서 밀려 분기점부터 비교합니다"
        case .degradeToHead: return "기준선 유실 — 현재 미커밋 변경만 보여줍니다"
        }
    }
}
