import Foundation

/// 서비스 = 프로젝트에 속한 장수 프로세스(`pnpm dev` 등). Bonsplit 탭 트리 **밖**에 산다
/// (탭이면 ⌘W가 dev 서버를 오살하고, 세션 복원·탭 그룹핑·배지 가시성 판정이 전부 특례를 요구한다).
///
/// 실행은 muxa 전용 tmux 서버(`-L muxa`)에 위임한다. 그 대가로 얻는 것:
///  - **생존**: tmux 서버는 launchd 소속(ppid=1)이라 muxa를 꺼도 프로세스가 살아남는다.
///  - **접힌 상태 감지**: 상태·로그를 서피스 렌더 없이 tmux CLI로 읽는다(list-panes / capture-pane).
///  - **재부착 레이스 회피**: 접을 때 서피스를 해제해도 프로세스는 tmux가 붙잡고 있다.
struct Service: Codable, Identifiable, Equatable {
    let id: String
    var name: String // 표시 이름 ("web")
    var command: String // 실행 명령 ("pnpm dev")
}

/// 서비스의 현재 상태. 진실 원천은 muxa가 아니라 tmux다 — 접혀 있어도 읽힌다.
enum ServiceState: Equatable {
    case running
    /// 죽었고 exit code를 안다. `remain-on-exit on` 덕에 죽은 뒤에도 pane이 남아 코드와 로그를 보존한다.
    /// code == -1 은 코드를 못 읽은 경우(신호 종료 등) — 죽었다는 사실만 확정.
    case exited(code: Int32)
    /// tmux에 세션이 없다(아직 시작 전이거나 정리됨).
    case missing
}

/// 서비스 ↔ tmux 세션 사이의 순수 로직 — 세션명 규약·출력 파싱·고아 판정·포트 추출.
/// 부작용(셸아웃)은 `TmuxService` 경계에만 두고 여기는 전부 순수 함수로 유지한다.
enum ServiceSession {
    /// 세션명 규약: `muxa__<projectId>__<serviceId>`.
    /// 접두사는 소유권 표식이다 — 이게 없는 세션은 파싱도 정리도 하지 않는다(남의 tmux 작업 보호).
    /// 구분자가 `__`인 이유: id로 쓰는 UUID에는 하이픈은 있어도 언더스코어가 없어 충돌하지 않는다.
    static let prefix = "muxa"
    static let separator = "__"

    static func name(projectId: String, serviceId: String) -> String {
        [prefix, projectId, serviceId].joined(separator: separator)
    }

    /// muxa 소유 세션명만 (projectId, serviceId)로 분해한다. 아니면 nil.
    static func parse(_ sessionName: String) -> (projectId: String, serviceId: String)? {
        let parts = sessionName.components(separatedBy: separator)
        guard parts.count == 3, parts[0] == prefix,
              !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (parts[1], parts[2])
    }

    /// `tmux list-panes -a -F '#{session_name}|#{pane_dead}|#{pane_dead_status}'` 출력 → 세션별 상태.
    /// 형식이 어긋난 줄은 조용히 버린다(상태를 지어내지 않는다).
    static func parsePanes(_ raw: String) -> [String: ServiceState] {
        var states: [String: ServiceState] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 3, !fields[0].isEmpty else { continue }
            let session = fields[0]
            if fields[1] == "1" {
                // 죽었다. status가 비면(신호 종료 등) 코드는 모르지만 죽었다는 사실은 확정이다.
                states[session] = .exited(code: Int32(fields[2]) ?? -1)
            } else {
                states[session] = .running
            }
        }
        return states
    }

    /// 정리해도 안전한 '고아' 세션(= 좀비 dev 서버)을 고른다. 순수, 부작용 없음.
    ///
    /// tmux 세션은 muxa가 죽어도 살아남는데(그게 이 설계의 존재 이유다), 그 대가로 등록이 사라진 뒤에도
    /// 프로세스가 남아 포트를 물고 있을 수 있다. 여기서 그걸 골라낸다.
    ///
    /// 보존(=건드리지 않음) 조건 — 하나라도 참이면 남긴다:
    ///  1) muxa 소유 세션이 아님 — 사용자의 다른 tmux 작업은 절대 죽이지 않는다(전용 소켓이라 원래
    ///     섞일 일이 없지만, 파괴적 동작이므로 판정에서 한 번 더 막는다)
    ///  2) 등록된 서비스에 대응함(serviceId ∈ liveServiceIds)
    static func orphans(sessions: [String], liveServiceIds: Set<String>) -> [String] {
        sessions.filter { session in
            guard let parsed = parse(session) else { return false }
            return !liveServiceIds.contains(parsed.serviceId)
        }
    }

    // MARK: 포트 추출 — 칩에 ':3000'을 띄우기 위한 최소 매칭

    /// 로그에서 리슨 포트를 뽑는다. 못 뽑으면 nil(그냥 이름만 표시한다 — 지어내지 않는다).
    ///
    /// **호스트가 앞에 붙은 형태만 인정한다.** `16:27:38` 같은 시각을 포트로 오인하면 칩이 거짓말을 하고,
    /// 그 순간 이 기능의 유일한 상시 신호가 신뢰를 잃는다. 로그 내용을 더 캐는 것(에러 감지 등)은
    /// 오탐 비용이 커서 v1에서 의도적으로 하지 않는다.
    private static let portPattern = try? NSRegularExpression(
        pattern: #"(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::\]|\[::1\]):(\d{2,5})"#)

    static func extractPort(_ log: String) -> Int? {
        guard let portPattern else { return nil }
        let range = NSRange(log.startIndex..<log.endIndex, in: log)
        // 마지막 매치 = 가장 최근 정보. 포트 충돌로 재시도한 경우 옛 포트가 아니라 지금 포트를 보여준다.
        guard let match = portPattern.matches(in: log, range: range).last,
              let portRange = Range(match.range(at: 1), in: log),
              let port = Int(log[portRange]), (1...65535).contains(port) else { return nil }
        return port
    }
}
