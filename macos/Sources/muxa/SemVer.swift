import Foundation

/// 시맨틱 버전 — 순수 값 타입.
///
/// 업데이트 판정의 핵심이다. **문자열 비교로 하면 안 된다**: `"0.10.0" < "0.3.0"`이 사전순으로
/// 참이라 새 버전을 옛 버전으로 오판한다. 그래서 정수 3튜플로 파싱해 `Comparable`로 비교한다.
///
/// 소스: 앱은 `CFBundleShortVersionString`(예: `0.3.0`)을, 원격은 GitHub 태그(예: `v0.4.0`)를 준다.
/// 둘 다 이 파서 하나로 받는다 — `v` 접두는 있으면 떼고, `major.minor.patch`만 읽는다.
/// pre-release/빌드 메타(`-rc.1`, `+build`)는 muxa 태그가 쓰지 않으므로 다루지 않는다(있으면 파싱 실패).
struct SemVer: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    /// `"v0.3.0"` · `"0.3.0"` → SemVer. 형식이 아니면 nil(무음 실패 — 호출부가 스킵한다).
    init?(parsing raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
