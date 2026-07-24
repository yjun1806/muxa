import Testing
@testable import muxa

/// 버전 비교(SSOT) — 사전순 비교의 함정(`0.10.0 < 0.3.0`)을 정수 3튜플로 못 박는다.
struct SemVerTests {
    @Test("v 접두는 있어도 없어도 같은 버전")
    func v접두_동일() {
        #expect(SemVer(parsing: "v0.3.0") == SemVer(parsing: "0.3.0"))
    }

    @Test("사전순 함정: 0.10.0 이 0.3.0 보다 크다")
    func 사전순함정() {
        let a = SemVer(parsing: "0.10.0")!
        let b = SemVer(parsing: "0.3.0")!
        #expect(a > b)
    }

    @Test("자리별 비교 — major > minor > patch 순")
    func 자리별비교() {
        #expect(SemVer(parsing: "1.0.0")! > SemVer(parsing: "0.99.99")!)
        #expect(SemVer(parsing: "0.4.0")! > SemVer(parsing: "0.3.9")!)
        #expect(SemVer(parsing: "0.3.2")! > SemVer(parsing: "0.3.1")!)
    }

    @Test("같은 버전은 크지도 작지도 않다")
    func 동일버전() {
        let a = SemVer(parsing: "0.3.0")!
        let b = SemVer(parsing: "v0.3.0")!
        #expect(!(a < b))
        #expect(!(a > b))
        #expect(a == b)
    }

    @Test("형식이 아니면 nil — 무음 실패")
    func 불량형식은nil() {
        #expect(SemVer(parsing: "") == nil)
        #expect(SemVer(parsing: "dev") == nil)
        #expect(SemVer(parsing: "0.3") == nil)          // 자리 부족
        #expect(SemVer(parsing: "0.3.0.1") == nil)      // 자리 초과
        #expect(SemVer(parsing: "0.3.x") == nil)        // 숫자 아님
        #expect(SemVer(parsing: "0.3.0-rc.1") == nil)   // pre-release 미지원
        #expect(SemVer(parsing: "-1.0.0") == nil)       // 음수
    }

    @Test("앞뒤 공백은 허용")
    func 공백허용() {
        #expect(SemVer(parsing: "  v0.3.0  ") == SemVer(parsing: "0.3.0"))
    }

    @Test("description 은 v 없는 정규형")
    func description정규형() {
        #expect(SemVer(parsing: "v0.3.0")!.description == "0.3.0")
    }
}
