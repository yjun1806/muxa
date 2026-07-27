import Foundation

/// 탭이 쓰던 **IDE 포트를 기억**해, 재시작해도 같은 탭이 같은 포트로 돌아오게 한다(YJ-3).
///
/// **왜 필요한가.** muxa는 터미널 생성 시 `CLAUDE_CODE_SSE_PORT`를 *값으로* 셸에 심는데, 셸은
/// tmux 페인에 살아서 **앱보다 오래 산다**. 재시작하면 muxa는 새 랜덤 포트를 잡지만 기존 페인의
/// env는 옛 번호 그대로다 — 고아가 된다.
///
/// 그리고 CLI(Claude Code)는 락파일을 훑을 때 **"락 포트 == env 포트"일 때만** 조상 검사를
/// 건너뛴다. muxa의 터미널은 tmux 서버(부모가 launchd인 데몬)가 띄우므로 muxa는 claude의 조상
/// 사슬에 **영원히 못 들어간다** — VS Code처럼 직계 부모가 되는 길이 없다. 즉 **포트 일치가
/// muxa에게 열린 유일한 통로**이고, 어긋나면 기존 탭은 `/ide`로도 다시 못 붙는다.
///
/// **키는 tmux 세션 이름**이다(탭 id가 아니다). muxa는 `TabID`를 저장하지 않고 `tmuxSession`
/// 문자열만 저장하므로, 재시작하면 탭 id는 새로 생성되고 저장된 세션 이름으로 재연결한다(실측).
/// 재시작을 넘어 사는 신원은 세션 이름뿐이고, 그게 곧 **옛 포트를 env에 물고 있는 그 셸**이라
/// 의미상으로도 정확하다. IDE env를 심는 조건(`tmuxSession != nil`)과도 정확히 겹친다.
///
/// 경계(파일 IO)와 순수(판정)를 가른다 — `IdeLockfile`과 같은 결.
enum IdePortStore {
    /// 인스턴스별 저장소 안에 둔다 — 릴리스와 개발 빌드가 서로의 포트를 넘보지 않게(디렉터리가 갈린다).
    static var path: String {
        MuxaSupportDir.url.appendingPathComponent("ide-ports.json").path
    }

    // MARK: 순수 — 판정

    /// 이 세션이 **다시 쓸** 포트. 1024 미만(0·특권 포트)은 무시한다 — 저장 파일이 손상됐거나 옛
    /// 형식이어도 엉뚱한 곳에 바인딩을 시도하지 않게 하는 방어선이다.
    static func preferredPort(_ map: [String: UInt16], for session: String) -> UInt16? {
        guard let port = map[session], port >= 1024 else { return nil }
        return port
    }

    /// 저장 파일 해석 — 깨졌거나 형식이 다르면 **빈 맵**(기억을 잃을 뿐, 랜덤 포트로 정상 동작).
    /// 범위를 벗어난 값은 통째로 버리지 않고 그 항목만 버린다.
    static func decode(_ data: Data) -> [String: UInt16] {
        guard let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return raw.compactMapValues { value in
            (1024...65535).contains(value) ? UInt16(value) : nil
        }
    }

    // MARK: 경계 — 파일 읽기/쓰기

    static func load() -> [String: UInt16] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        return decode(data)
    }

    /// 실패는 무시한다 — 포트 기억은 편의 기능이라, 못 써도 랜덤 포트로 지금까지처럼 동작한다.
    static func save(_ map: [String: UInt16]) {
        guard let data = try? JSONEncoder().encode(map.mapValues { Int($0) }) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
