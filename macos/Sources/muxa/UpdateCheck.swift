import Foundation

/// 업데이트 판정 — 순수 로직(부작용 없음).
///
/// 네트워크(GitHub 태그 조회)와 UI에서 **판정만** 떼어낸 곳이다. 경계(`UpdateChecker`)는 태그 문자열
/// 목록을 가져오기만 하고, "무엇이 최신인가 · 업데이트인가"는 전부 여기서 정해 테스트로 못 박는다.
enum UpdateCheck {
    /// 태그 이름 목록(`["v0.3.0", "v0.2.0", …]`) → 그중 **가장 높은 semver**.
    ///
    /// GitHub tags API는 정렬을 보장하지 않으므로 정렬에 기대지 않고 우리가 최대를 고른다.
    /// 파싱 안 되는 태그(비-semver·릴리스 아닌 태그)는 조용히 버린다. 하나도 없으면 nil.
    static func latest(fromTagNames names: [String]) -> SemVer? {
        names.compactMap(SemVer.init(parsing:)).max()
    }

    /// 현재 버전보다 원격 최신이 **엄격히 높을 때만** 업데이트다.
    ///
    /// - current 파싱 실패(dev 빌드의 `"dev"`·`"0.0.0"` 등) → 업데이트 아님(개발빌드 nag 금지).
    /// - 같거나 낮으면(로컬이 태그보다 앞선 경우 포함) → 업데이트 아님.
    static func isUpdateAvailable(current currentRaw: String, latest: SemVer?) -> Bool {
        guard let latest, let current = SemVer(parsing: currentRaw) else { return false }
        return latest > current
    }
}
