import Foundation
import Testing
@testable import muxa

/// 소켓 열거의 판정(순수) — 세션 관리자는 앱 자신의 소켓 **하나**(D19 격리)가 아니라 이 머신의
/// muxa 소켓을 전부 읽는다. 그 "전부"의 경계와 순서가 여기서 정해진다.
///
/// 규칙이 어긋나면 증상이 **침묵**이다 — 소켓을 못 찾으면 창이 그냥 비어 보이고, 정렬이 없으면
/// 폴링마다 표의 행이 뒤바뀐다. 둘 다 눈으로는 "버그가 아닌 것"처럼 보인다.
struct TmuxSocketScannerTests {
    /// 실측 목록(2026-07-29 `/private/tmp/tmux-501/`)에 남의 소켓을 섞은 것 — muxa 것만 남는다.
    @Test func picksOnlyMuxaSockets() {
        let got = TmuxSocketScanner.muxaSockets(in: [
            "muxa-services", "muxa-services-muxa-98d167", "muxa_test_10957", "muxa_q_13598",
            "default", "tmate-abc123",
        ])
        #expect(got == ["muxa-services", "muxa-services-muxa-98d167", "muxa_q_13598", "muxa_test_10957"])
    }

    /// 릴리스 소켓이 맨 앞 — 목록 첫 줄은 "보통 쓰는 그것"이어야 한다.
    @Test func releaseSocketSortsFirst() {
        let got = TmuxSocketScanner.muxaSockets(in: ["muxa_test_1", "muxa-services-dev-abc", "muxa-services"])
        #expect(got.first == TmuxSocketScanner.releaseSocket)
    }

    /// 나머지는 이름순. `contentsOfDirectory`의 순서는 보장이 없어서, 정렬하지 않으면
    /// 폴링(2초)마다 행 순서가 흔들려 클릭이 빗나간다.
    @Test func restSortsByName() {
        #expect(TmuxSocketScanner.muxaSockets(in: ["muxa_b", "muxa_a"]) == ["muxa_a", "muxa_b"])
    }

    /// muxa 소켓이 하나도 없어도 죽지 않는다(tmux를 한 번도 안 쓴 머신).
    @Test func emptyWhenNoMuxaSockets() {
        #expect(TmuxSocketScanner.muxaSockets(in: ["default", "tmate-x"]).isEmpty)
    }

    /// 소켓 → 사람이 읽는 이름. 릴리스는 이름이 규약이라 그대로 두면 무슨 소켓인지 안 보인다.
    @Test func labelsSockets() {
        #expect(TmuxSocketScanner.label(for: "muxa-services") == "릴리스")
        #expect(TmuxSocketScanner.label(for: "muxa-services-muxa-98d167") == "muxa-98d167")
        #expect(TmuxSocketScanner.label(for: "muxa-services-muxa-cross-pane-context-3c8084")
                == "muxa-cross-pane-context-3c8084")
        // 우리 규약 밖의 소켓(출처 미상)은 이름을 그대로 보여준다 — 지어내면 추적이 끊긴다.
        #expect(TmuxSocketScanner.label(for: "muxa_test_10957") == "muxa_test_10957")
    }

    /// **tmux와 같은 규칙이어야 한다** — `TMUX_TMPDIR`가 비어있지 않으면 그것, 아니면 `/tmp`.
    /// 어긋나면 소켓을 하나도 못 찾고, 그 실패는 "세션이 없다"로 보인다.
    @Test func socketDirectoryFollowsTmuxRule() {
        #expect(TmuxSocketScanner.directory(tmpdir: "/custom", uid: 501).path == "/custom/tmux-501")
        #expect(TmuxSocketScanner.directory(tmpdir: nil, uid: 501).path == "/tmp/tmux-501")
        // env가 **빈 문자열**인 경우 — 설정한 적 없는 것과 같게 다뤄야 한다(tmux가 그렇게 한다).
        #expect(TmuxSocketScanner.directory(tmpdir: "", uid: 501).path == "/tmp/tmux-501")
    }

    /// 릴리스 소켓 이름은 `TmuxService.socket`의 릴리스 갈래와 **같은 값이어야 한다**.
    /// 둘이 어긋나면 관리자가 정작 릴리스 앱의 세션을 "남의 소켓"으로 라벨링한다.
    @Test func releaseSocketMatchesTmuxService() {
        #expect(TmuxSocketScanner.releaseSocket == "muxa-services")
    }
}
