import Foundation

/// 스크립트 실행을 tmux 세션에 담는 규약(순수) — 서비스·터미널과 **같은 전용 소켓, 다른 네임스페이스**:
///
///     서비스     muxa__<projectId>__<serviceId>
///     터미널     muxa__<projectId>__term__<tabId>
///     스크립트   muxa__<projectId>__script__<scriptId>
///
/// 네임스페이스를 가르는 이유(TerminalSession과 동일): 서비스 고아 정리(`ServiceSession.orphans`)는
/// "등록에 없는 muxa 세션"을 **죽인다**. `ServiceSession.parse`가 `__` 3조각만 인정하므로 4조각인
/// 스크립트 세션은 그 판정에서 자동으로 빠지고, `TerminalSession.parse`는 marker가 `term`이 아니면
/// 버리므로 터미널 GC에도 안 걸린다 — 그래도 우연에 기대지 않도록 규약을 명시하고 테스트로 고정한다.
///
/// 부작용(셸아웃)은 `TmuxService` 경계에만 두고 여기는 전부 순수 함수로 유지한다.
enum ScriptSession {
    /// 스크립트 네임스페이스 표식. 조각 수(4)는 터미널과 같고 marker가 다르다.
    static let marker = "script"

    /// 세션명. **id가 규약을 벗어나면 이름을 만들지 않는다** — 세션을 만들지 못하는 편이,
    /// 손댈 수 없는 좀비를 만드는 것보다 낫다(ServiceSession.name과 같은 판단·같은 화이트리스트).
    static func name(projectId: String, scriptId: String) -> String? {
        guard ServiceSession.isValidId(projectId), ServiceSession.isValidId(scriptId) else { return nil }
        return [ServiceSession.prefix, projectId, marker, scriptId]
            .joined(separator: ServiceSession.separator)
    }

    /// muxa 소유 **스크립트** 세션명만 분해한다. 서비스·터미널·남의 세션은 nil.
    static func parse(_ sessionName: String) -> (projectId: String, scriptId: String)? {
        let parts = sessionName.components(separatedBy: ServiceSession.separator)
        guard parts.count == 4,
              parts[0] == ServiceSession.prefix,
              parts[2] == marker,
              !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return (parts[1], parts[3])
    }

    /// 정리해도 안전한 '고아' 스크립트 세션 — 등록이 사라졌는데 살아남은 것들.
    ///
    /// 보존(=건드리지 않음) 조건 — 하나라도 참이면 남긴다(서비스·터미널 GC와 같은 원칙):
    ///  1) 스크립트 세션이 아님 — 서비스·터미널·남의 tmux 작업은 판정 대상이 아니다
    ///  2) **내가 모르는 프로젝트의 세션** — 다른 muxa 인스턴스의 것일 수 있다(소켓 공유)
    ///  3) 등록된 스크립트에 대응함(scriptId ∈ liveScriptIds) — 종료된 실행의 로그도
    ///     등록이 살아 있는 한 보존된다(종료 로그를 봐야 하므로 끝났다고 지우면 안 된다)
    static func orphans(sessions: [String], liveScriptIds: Set<String>,
                        knownProjectIds: Set<String>) -> [String] {
        sessions.filter { session in
            guard let parsed = parse(session) else { return false }
            guard knownProjectIds.contains(parsed.projectId) else { return false }
            return !liveScriptIds.contains(parsed.scriptId)
        }
    }
}
