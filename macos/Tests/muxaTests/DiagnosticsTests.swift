import Testing
@testable import muxa

/// 진단 정보 — 사용자가 문제를 보고할 때 붙일 한 덩어리 텍스트(순수 조립).
struct DiagnosticsTests {
    @Test("보고에 필요한 값이 모두 담긴다")
    func 필수항목포함() {
        let text = Diagnostics.report(name: "muxa", version: "1.2.0", build: "42",
                                      os: "Version 15.3 (Build 24D60)",
                                      supportDir: "/Users/x/Library/Application Support/muxa",
                                      lastLaunchWasDirty: true)
        #expect(text.contains("muxa 1.2.0 (42)"))
        #expect(text.contains("Version 15.3"))
        #expect(text.contains("/Users/x/Library/Application Support/muxa"))
        #expect(text.contains("비정상"))
    }

    @Test("정상 종료였으면 정상으로 표기한다")
    func 정상종료표기() {
        let text = Diagnostics.report(name: "muxa", version: "dev", build: "-", os: "macOS",
                                      supportDir: "/tmp", lastLaunchWasDirty: false)
        #expect(text.contains("직전 종료: 정상"))
        #expect(!text.contains("비정상"))
    }
}
