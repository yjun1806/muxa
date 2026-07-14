import Testing
@testable import muxa

/// 재개 명령을 보내도 되는가 — 순수 판정(ResumeGate). 실행은 되돌릴 수 없다(sendText가 Enter까지 친다).
/// 그래서 "보낸다"는 판정을 좁게 못 박는다: 셸 프롬프트 + 정확한 폴더일 때만.
///
/// 특히 **모르는 것(.notReady)과 틀린 것(.foregroundBusy/.wrongCwd)을 가른다** — 전자는 시간이 해결하므로
/// auto가 재시도하고, 후자는 사용자가 조건을 바꿔야 하므로 배너로 넘긴다. 둘을 뭉개면 auto가 죽거나(전부 차단)
/// 검사가 무의미해진다(전부 통과).
@Suite("ResumeGate — 재개 실행 게이트")
struct ResumeGateTests {
    @Test("셸 프롬프트 + 경로 일치 → 보낸다")
    func sendsWhenShellAndCwdMatch() {
        let d = ResumeGate.decide(expectedCwd: "/Users/x/repo", pwd: "/Users/x/repo", foregroundIsShell: true)
        #expect(d == .send)
    }

    /// 회귀: 살아 있는 claude(TUI) 입력창에 `claude --resume …`를 타이핑하던 버그.
    @Test("포그라운드가 TUI면 보내지 않는다 — 남의 입력창에 명령을 꽂지 않는다")
    func holdsWhenForegroundIsNotShell() {
        let d = ResumeGate.decide(expectedCwd: "/Users/x/repo", pwd: "/Users/x/repo", foregroundIsShell: false)
        #expect(d == .hold(.foregroundBusy))
    }

    /// 셸 pid는 스폰 후 폴링(250ms)으로 잡힌다 — 그 전 구간을 "셸이다"로 가정하면 검사를 안 한 것과 같다.
    /// 캡처 경로는 "모르면 한다"가 안전하지만, 명령 전송은 정반대다.
    @Test("포그라운드를 아직 모르면(pid 미확보) 보내지 않는다 — 모르면 안 보낸다")
    func holdsWhenForegroundUnknown() {
        let d = ResumeGate.decide(expectedCwd: "/Users/x/repo", pwd: "/Users/x/repo", foregroundIsShell: nil)
        #expect(d == .hold(.notReady))
    }

    /// 우선순위: 포그라운드 → 경로. TUI가 잡고 있으면 경로가 맞아도 못 보낸다.
    @Test("TUI면 경로가 맞아도 포그라운드 보류가 우선한다")
    func foregroundCheckPrecedesCwd() {
        let d = ResumeGate.decide(expectedCwd: nil, pwd: nil, foregroundIsShell: false)
        #expect(d == .hold(.foregroundBusy))
    }

    @Test("셸이 다른 폴더에 있으면 보내지 않는다 — 그 폴더엔 이 세션이 없다")
    func holdsWhenCwdDiffers() {
        let d = ResumeGate.decide(expectedCwd: "/Users/x/repo", pwd: "/Users/x/other", foregroundIsShell: true)
        #expect(d == .hold(.wrongCwd(expected: "/Users/x/repo")))
    }

    /// 셸이 떴지만 첫 프롬프트(OSC 7) 전이라 pwd를 모르는 구간 — 추측해서 보내지 않고 기다린다.
    @Test("기대 경로가 있는데 현재 pwd를 모르면 보류한다(틀린 게 아니라 이르다)")
    func holdsWhenPwdUnknown() {
        let d = ResumeGate.decide(expectedCwd: "/Users/x/repo", pwd: nil, foregroundIsShell: true)
        #expect(d == .hold(.notReady))
    }

    /// 기록이 없는 것은 "틀렸다"가 아니라 "모른다" — 구 스냅샷의 바인딩까지 죽이지 않는다.
    @Test("바인딩에 cwd가 없으면(구 스냅샷) 경로 검사를 건너뛴다")
    func skipsCwdCheckWhenBindingHasNone() {
        let d = ResumeGate.decide(expectedCwd: nil, pwd: "/anywhere", foregroundIsShell: true)
        #expect(d == .send)
    }

    /// 기대 경로는 claude의 물리 경로, pwd는 셸의 논리 경로다. 심링크는 호출부가 해석하고,
    /// **대소문자는 여기서** 흡수한다 — APFS 기본이 case-insensitive라 `cd /users/…`도 같은 폴더다.
    @Test("끝의 슬래시·대소문자 차이는 같은 경로로 본다", arguments: [
        ("/Users/x/repo/", "/Users/x/repo"),
        ("/Users/x/repo", "/Users/x/repo/"),
        ("/users/x/REPO", "/Users/x/repo"),
        ("/", "/"),
    ])
    func trailingSlashAndCaseAreIgnored(pwd: String, expected: String) {
        #expect(ResumeGate.isSamePath(pwd, expected))
        #expect(ResumeGate.decide(expectedCwd: expected, pwd: pwd, foregroundIsShell: true) == .send)
    }

    @Test("상위·하위 폴더는 같은 경로가 아니다")
    func nestedPathsDiffer() {
        #expect(!ResumeGate.isSamePath("/Users/x/repo/sub", "/Users/x/repo"))
        #expect(!ResumeGate.isSamePath("/Users/x/rep", "/Users/x/repo"))
    }
}
