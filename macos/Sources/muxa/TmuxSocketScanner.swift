import Foundation

/// 이 머신의 muxa tmux 소켓을 찾는다 — 세션 관리자가 "숨은 tmux"를 보여주기 위한 입구.
///
/// 앱 자신은 소켓 **하나**만 쓴다(`TmuxService.socket`). 개발빌드마다 소켓을 가르는 그 격리는
/// *"정리가 파괴적 동작이라"* 도입된 것이지(`TmuxService.swift:18`) 관측을 막으려는 게 아니다.
/// 그래서 이 스캐너는 전부 읽고, 격리는 **죽이는 쪽에서만** 지킨다.
///
/// 읽기를 자기 소켓으로 좁히면 문제 자체가 안 보인다: 실측(2026-07-29)에서 이 머신의 muxa 소켓은
/// 17개인데 릴리스 앱이 보는 것은 1개뿐이었다.
enum TmuxSocketScanner {
    /// muxa가 만드는 소켓의 공통 접두사. `TmuxService.socket`의 두 갈래(릴리스·dev)가 모두 이걸로 시작한다.
    static let prefix = "muxa"

    /// 릴리스 빌드의 소켓 이름 — `TmuxService.socket`의 `devKey == nil` 갈래와 **같은 값이어야 한다**
    /// (테스트로 고정). 어긋나면 정작 릴리스 앱의 세션이 "출처 미상 소켓"으로 라벨링된다.
    static let releaseSocket = "muxa-services"

    /// tmux가 소켓을 두는 디렉터리(순수) — **tmux와 같은 규칙이어야 한다.**
    /// tmux는 `TMUX_TMPDIR`가 비어있지 않으면 그것을, 아니면 `/tmp`를 쓰고 그 아래 `tmux-<uid>`를 만든다.
    /// 규칙이 어긋나면 소켓을 하나도 못 찾는데, 그 실패는 화면에서 "세션이 없다"로 보인다(침묵).
    static func directory(tmpdir: String?, uid: uid_t) -> URL {
        let base = tmpdir.flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp"
        return URL(fileURLWithPath: base).appendingPathComponent("tmux-\(uid)")
    }

    /// 이 프로세스 기준 소켓 디렉터리.
    static var directory: URL {
        directory(tmpdir: ProcessInfo.processInfo.environment["TMUX_TMPDIR"], uid: getuid())
    }

    /// muxa 소켓만 골라 **안정된 순서**로 돌려준다(순수).
    ///
    /// 릴리스 소켓이 맨 앞, 나머지는 이름순. `contentsOfDirectory`는 순서를 보장하지 않으므로
    /// 정렬하지 않으면 폴링(2초)마다 표의 행이 뒤바뀌어 클릭이 빗나간다.
    static func muxaSockets(in names: [String]) -> [String] {
        names.filter { $0.hasPrefix(prefix) }.sorted { a, b in
            switch (a == releaseSocket, b == releaseSocket) {
            case (true, false): return true
            case (false, true): return false
            default: return a < b
            }
        }
    }

    /// 사람이 읽는 소켓 이름(순수). 규약 밖의 소켓은 **이름을 그대로** 보여준다 —
    /// 지어내면 출처 추적이 끊긴다(이 머신의 `muxa_test_*` 10개가 그런 경우다).
    static func label(for socket: String) -> String {
        if socket == releaseSocket { return "릴리스" }
        let devPrefix = releaseSocket + "-"
        if socket.hasPrefix(devPrefix) { return String(socket.dropFirst(devPrefix.count)) }
        return socket
    }

    /// 실제 디렉터리를 훑는다. 디렉터리가 없거나 못 읽으면 빈 목록 —
    /// tmux를 한 번도 안 쓴 머신에서도 창은 떠야 한다.
    static func scan() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return muxaSockets(in: names)
    }
}
