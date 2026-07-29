import Foundation
import Testing
@testable import muxa

/// "이 세션은 누구 것인가"의 판정(순수) — 소켓의 주인과 지금 보고 있는 GUI.
///
/// 두 질문 다 틀리면 표가 거짓말을 한다. 고아 표시는 **자기 인스턴스 기준으로 남의 세션을 재면
/// 전부 고아로 뜨고**(실측에서 41개 중 40개가 그렇게 잘못 표시됐다), 연결 상태는 "어느 GUI에
/// 붙었는지"와 "완전히 분리됐는지"가 뭉개지면 정작 찾아야 할 것을 못 찾는다.
struct SessionOwnershipTests {
    // MARK: 소켓 → 그 인스턴스의 지원 폴더

    /// 릴리스 소켓의 짝은 `muxa` 폴더다.
    @Test func releaseSocketMapsToPlainFolder() {
        #expect(SessionOwnership.supportFolder(for: "muxa-services") == "muxa")
    }

    /// dev 소켓은 devKey를 그대로 물려준다 — 실측으로 검증된 대응이다
    /// (`muxa-services-muxa-2b410b` ↔ `muxa-dev-muxa-2b410b`).
    @Test func devSocketMapsToDevFolder() {
        #expect(SessionOwnership.supportFolder(for: "muxa-services-muxa-2b410b") == "muxa-dev-muxa-2b410b")
        #expect(SessionOwnership.supportFolder(for: "muxa-services-muxa-cross-pane-context-3c8084")
                == "muxa-dev-muxa-cross-pane-context-3c8084")
    }

    /// 규약 밖 소켓(출처 미상)은 짝이 없다 — 지어내면 엉뚱한 state로 남의 세션을 고아라 부른다.
    @Test func foreignSocketHasNoFolder() {
        #expect(SessionOwnership.supportFolder(for: "muxa_test_10957") == nil)
        #expect(SessionOwnership.supportFolder(for: "default") == nil)
    }

    /// **소켓 이름은 디렉터리 목록에서 온다 — 신뢰 경계 밖이다.**
    /// 그대로 경로에 붙이면 `..`가 섞인 이름이 지원 폴더 밖의 파일을 읽게 한다.
    @Test func rejectsPathTraversalInSocketName() {
        #expect(SessionOwnership.supportFolder(for: "muxa-services-../../../etc") == nil)
        #expect(SessionOwnership.supportFolder(for: "muxa-services-a/b") == nil)
        #expect(SessionOwnership.supportFolder(for: "muxa-services-..") == nil)
        // 정상 이름은 그대로 통과해야 한다(과잉 차단 방지).
        #expect(SessionOwnership.supportFolder(for: "muxa-services-muxa-2b410b") == "muxa-dev-muxa-2b410b")
    }

    // MARK: 연결 상태 — 어느 GUI가 보고 있나

    /// pid → (ppid, 이름) 표본으로 트리를 짓는다.
    private func snapshot(_ entries: [(pid_t, pid_t, String)]) -> ProcessSnapshot {
        ProcessSnapshot(samples: entries.reduce(into: [:]) { acc, e in
            acc[e.0] = ProcessSample(pid: e.0, ppid: e.1, name: e.2, cpuNanos: 0, footprintBytes: 0)
        }, uptime: 0)
    }

    /// 실측 체인: `tmux(34168) → zsh → login → muxa(34125) → launchd`.
    private let chain: [(pid_t, pid_t, String)] = [
        (1, 0, "launchd"),
        (34125, 1, "muxa"),          // 릴리스 앱
        (34165, 34125, "login"),
        (34167, 34165, "zsh"),
        (34168, 34167, "tmux"),      // 클라이언트
        (99000, 1, "muxa-dev-main"), // 다른 인스턴스
        (99001, 99000, "login"),
        (99002, 99001, "tmux"),
        (5000, 1, "iTerm2"),         // muxa가 아닌 터미널
        (5001, 5000, "tmux"),
    ]

    /// 붙은 클라이언트가 없으면 **완전 분리** — 이 창이 찾아야 할 상태다.
    @Test func noClientsMeansDetached() {
        #expect(SessionOwnership.attachment(clientPids: [], snapshot: snapshot(chain), ownAppPid: 34125)
                == .detached)
    }

    /// 클라이언트의 조상이 나 자신이면 **이 앱의 탭**이다.
    @Test func ancestorIsOwnAppMeansThisApp() {
        #expect(SessionOwnership.attachment(clientPids: [34168], snapshot: snapshot(chain), ownAppPid: 34125)
                == .thisApp)
    }

    /// 조상이 다른 muxa면 그 앱 이름을 말해준다 — "릴리스에서 보고 있다"를 알아야 안 죽인다.
    @Test func ancestorIsAnotherMuxaMeansOtherApp() {
        #expect(SessionOwnership.attachment(clientPids: [99002], snapshot: snapshot(chain), ownAppPid: 34125)
                == .otherApp("muxa-dev-main"))
    }

    /// muxa가 아닌 터미널에서 직접 attach한 경우 — 사용자가 손으로 붙은 것이다.
    @Test func ancestorIsNotMuxaMeansExternal() {
        #expect(SessionOwnership.attachment(clientPids: [5001], snapshot: snapshot(chain), ownAppPid: 34125)
                == .external)
    }

    /// **내 앱이 우선이다.** 여럿이 붙어 있으면 "내가 보고 있다"가 가장 중요한 사실이다.
    @Test func ownAppWinsWhenMultipleClients() {
        #expect(SessionOwnership.attachment(clientPids: [5001, 99002, 34168],
                                            snapshot: snapshot(chain), ownAppPid: 34125) == .thisApp)
    }

    /// **조상을 못 찾아도 분리는 아니다.** tmux가 클라이언트를 보고했으면 누군가는 붙어 있다 —
    /// 표본이 늦었거나 방금 죽은 pid일 뿐이다. 붙어 있는 걸 "분리됨"이라 표시하면 사람이 그걸 근거로
    /// 남의 화면을 죽인다. 반대 실수(안 붙은 걸 붙었다고 하는 것)는 안 죽이고 넘어가는 것뿐이라 싸다.
    @Test func unknownClientStillCountsAsAttached() {
        #expect(SessionOwnership.attachment(clientPids: [77777], snapshot: snapshot(chain), ownAppPid: 34125)
                == .external)
    }

    /// 클라이언트 목록 파싱 — `#{client_session}|#{client_pid}` 한 줄씩.
    @Test func parsesClientList() {
        let raw = """
        muxa__P__term__A|34168
        muxa__P__term__A|34171
        muxa__P__term__B|34950
        쓰레기줄
        """
        let bySession = SessionOwnership.parseClients(raw)
        #expect(bySession["muxa__P__term__A"] == [34168, 34171])
        #expect(bySession["muxa__P__term__B"] == [34950])
        #expect(bySession.count == 2)
    }
}
