import Testing
@testable import muxa

/// 업데이트 판정(SSOT) — 최신 태그 선정과 "업데이트인가" 판정을 순수 함수로 못 박는다.
struct UpdateCheckTests {
    @Test("정렬 안 된 태그 목록에서 최대 semver를 고른다")
    func 최대선정() {
        let latest = UpdateCheck.latest(fromTagNames: ["v0.2.0", "v0.10.0", "v0.3.0", "v0.1.0"])
        #expect(latest == SemVer(parsing: "0.10.0"))
    }

    @Test("비-semver 태그는 버린다")
    func 비semver버림() {
        let latest = UpdateCheck.latest(fromTagNames: ["nightly", "v0.3.0", "release", "v0.2.0"])
        #expect(latest == SemVer(parsing: "0.3.0"))
    }

    @Test("파싱 가능한 태그가 없으면 nil")
    func 태그없음() {
        #expect(UpdateCheck.latest(fromTagNames: []) == nil)
        #expect(UpdateCheck.latest(fromTagNames: ["latest", "stable"]) == nil)
    }

    @Test("원격이 더 높을 때만 업데이트")
    func 업데이트있음() {
        #expect(UpdateCheck.isUpdateAvailable(current: "0.3.0", latest: SemVer(parsing: "0.4.0")))
    }

    @Test("같은 버전은 업데이트 아님")
    func 동일버전은아님() {
        #expect(!UpdateCheck.isUpdateAvailable(current: "0.3.0", latest: SemVer(parsing: "0.3.0")))
    }

    @Test("로컬이 태그보다 앞서면 업데이트 아님")
    func 로컬이앞섬() {
        #expect(!UpdateCheck.isUpdateAvailable(current: "0.5.0", latest: SemVer(parsing: "0.4.0")))
    }

    @Test("dev 빌드는 nag 하지 않는다 — current 파싱 실패")
    func dev빌드는nag안함() {
        #expect(!UpdateCheck.isUpdateAvailable(current: "dev", latest: SemVer(parsing: "0.4.0")))
    }

    @Test("0.0.0 도 유효 semver라 0.4.0 이면 업데이트로 본다")
    func 제로버전판정() {
        #expect(UpdateCheck.isUpdateAvailable(current: "0.0.0", latest: SemVer(parsing: "0.4.0")))
    }

    @Test("원격 최신이 nil 이면 업데이트 아님")
    func 최신없으면아님() {
        #expect(!UpdateCheck.isUpdateAvailable(current: "0.3.0", latest: nil))
    }
}
