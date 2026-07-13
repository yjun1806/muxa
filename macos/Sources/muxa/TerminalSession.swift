import Foundation

/// 터미널 탭을 tmux 세션에 담는 규약(순수) — 앱을 꺼도 셸·에이전트·빌드가 살아남게 한다(L3).
///
/// 서비스([[Service]])와 **같은 전용 소켓(`-L muxa`)에 살지만 네임스페이스가 다르다**:
///
///     서비스   muxa__<projectId>__<serviceId>
///     터미널   muxa__<projectId>__term__<tabId>
///
/// 이 분리가 중요한 이유: 서비스 고아 정리(`ServiceSession.orphans`)는 "등록에 없는 muxa 세션"을
/// **죽인다**. 터미널 세션이 그 판정에 걸리면 멀쩡히 돌던 셸이 전부 죽는다. `ServiceSession.parse`가
/// `__` 3조각만 인정하므로 4조각인 터미널 세션은 그 판정에서 자동으로 빠진다 — 그래도 우연에
/// 기대지 않도록 여기서 규약을 명시하고 테스트로 고정한다.
enum TerminalSession {
    /// 터미널 네임스페이스 표식. 서비스 세션과 조각 수가 달라 서로의 파서에 걸리지 않는다.
    static let marker = "term"

    static func name(projectId: String, tabId: String) -> String {
        [ServiceSession.prefix, projectId, marker, tabId].joined(separator: ServiceSession.separator)
    }

    /// muxa 소유 **터미널** 세션명만 분해한다. 서비스 세션·남의 세션은 nil.
    static func parse(_ sessionName: String) -> (projectId: String, tabId: String)? {
        let parts = sessionName.components(separatedBy: ServiceSession.separator)
        guard parts.count == 4,
              parts[0] == ServiceSession.prefix,
              parts[2] == marker,
              !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return (parts[1], parts[3])
    }

    /// 이 탭의 셸을 tmux 세션 안에서 띄우는 명령(순수). `TermView.initialCommand`로 셸에 주입한다.
    ///
    /// 한 줄에 네 가지를 순서대로 한다 — **셋 다 빠지면 조용히 깨진다**:
    ///  1. `new-session -d` — 없으면 만들고, 있으면 실패(무시)한다. 앱을 껐다 켜도 같은 이름이면 그대로 붙는다.
    ///  2. `remain-on-exit off` — 서버 전역은 `on`이다(서비스가 죽은 뒤 exit code·로그를 읽어야 하므로).
    ///     터미널에 그대로 두면 사용자가 `exit`를 쳐도 pane이 죽은 채 남아 탭이 안 닫히고 세션이 쌓인다.
    ///  3. `allow-passthrough on` — tmux는 안쪽 OSC를 자체 소비한다. 이걸 켜야 셸 통합이
    ///     `\ePtmux;…\e\\`로 감싼 OSC 7(cwd)·133(완료)이 muxa까지 나온다. 없으면 경로 추적과
    ///     완료 배지·알림이 통째로 죽는다(실측).
    ///  4. `attach` — 붙는다. **exec를 쓰지 않는다**: detach하면 셸 프롬프트로 돌아와 탭이 살아남는다.
    ///
    /// zsh에서 `=word`는 명령 경로로 치환되는 EQUALS 확장이라 타겟은 반드시 인용한다(서비스 attach와 동일).
    /// - Parameter session: **세션명을 그대로 받는다.** 복원된 탭은 저장된 이름을 이어받아야 하는데,
    ///   여기서 tabId로 재조립하면 새로 발급된 id로 엉뚱한 세션을 만든다(§tmuxSession).
    /// - Parameter env: 세션 안 셸에 심을 환경변수(`-e`). **비우면 훅과 셸 통합이 통째로 죽는다** —
    ///   tmux 세션의 셸은 tmux **서버**의 환경을 상속하지, ghostty가 띄운 바깥 셸의 env를 받지 않는다.
    ///   그래서 MUXA_TAB_ID·MUXA_SOCK이 없어 `muxa notify`가 어느 탭인지 못 찾고(알림·배지 소실),
    ///   rc 스니펫도 조건이 안 맞아 OSC를 안 쏜다(cwd 추적 소실). 실측으로 확인한 실패다.
    static func startCommand(tmux: String, socket: String, session: String, cwd: String,
                             env: [String: String] = [:]) -> String {
        let t = "\(tmux) -L \(socket)"
        // -e는 **세션을 새로 만들 때만** 적용된다(이미 있으면 무시). 복원된 세션의 셸에는 옛 tabId가
        // 남아 있는데, 그건 세션명으로 되짚어 현재 탭을 찾는다(§resolve).
        let envArgs = env.keys.sorted().map { " -e '\($0)=\(env[$0]!)'" }.joined()
        let q = "'\(session)'"
        return [
            "\(t) new-session -d -s \(q) -c '\(cwd)'\(envArgs) 2>/dev/null",
            "\(t) set-option -t \(q) remain-on-exit off 2>/dev/null",
            "\(t) set-option -g allow-passthrough on 2>/dev/null",
            // 탭 이름 — tmux는 기본으로 자기 제목(= `tmux … attach …` 명령줄)을 내보내, 탭 이름이
            // 그 문자열로 굳는다(실측). 안쪽 셸이 있는 폴더를 대신 전파해 자동 명명을 되살린다.
            "\(t) set-option -g set-titles on 2>/dev/null",
            "\(t) set-option -g set-titles-string '#{b:pane_current_path}' 2>/dev/null",
            "\(t) attach -t '=\(session)'",
        ].joined(separator: "; ")
    }

    /// 훅이 보낸 tabId를 **현재 살아있는 탭**으로 되짚는다(순수).
    ///
    /// tmux 세션 안 셸의 `MUXA_TAB_ID`는 **그 세션이 처음 만들어질 때의 tabId**다. 복원하면 tabId가
    /// 새로 발급되는데(Bonsplit `createTab`은 id를 지정받지 않는다) 세션 안 셸의 env는 그대로다.
    /// 그래서 훅은 옛 id로 신호를 보내고, 그대로 두면 muxa가 **어느 탭인지 못 찾아 알림이 사라진다**.
    ///
    /// 다행히 세션명이 다리가 된다: `muxa__<projectId>__term__<처음tabId>`. 현재 탭이 어떤 세션을
    /// 쓰는지는 muxa가 알고 있으므로(§tmuxSessions), 세션명에 박힌 옛 id로 현재 탭을 되찾을 수 있다.
    ///
    /// - Parameter sessionsByTab: 현재 tabId → 세션명.
    /// - Returns: 신호를 배달할 현재 tabId. 매칭이 없으면 nil(호출부가 원래 id를 그대로 쓴다).
    static func resolve(incomingTabId: String, sessionsByTab: [String: String]) -> String? {
        // 살아있는 탭 id면 그대로 — tmux를 안 쓰는 탭·같은 세션에서 새로 만든 탭의 정상 경로.
        if sessionsByTab[incomingTabId] != nil { return incomingTabId }
        for (currentTab, session) in sessionsByTab {
            if let parsed = parse(session), parsed.tabId == incomingTabId { return currentTab }
        }
        return nil
    }

    /// 정리해도 안전한 고아 터미널 세션 — 살아있는 탭이 참조하지 않는 것들.
    ///
    /// 보존(=건드리지 않음) 조건 — 하나라도 참이면 남긴다:
    ///  1) 터미널 세션이 아님 — 서비스 세션·남의 tmux 작업은 판정 대상이 아니다
    ///  2) **내가 모르는 프로젝트의 세션** — muxa 인스턴스는 여럿 떠 있을 수 있고(창 여러 개, 워크트리
    ///     빌드) 같은 tmux 소켓을 공유한다. 내 state에 없는 프로젝트의 세션은 남의 것이다. 이 가드가
    ///     없으면 인스턴스끼리 서로의 셸을 몰살한다(서비스 GC가 같은 이유로 배운 가드다).
    ///  3) 살아있는 탭이 참조함
    ///
    /// 판정 입력 `liveSessionNames`는 **스냅샷이 참조하는 세션명 전부**여야 한다. 열려 있는 탭만
    /// 넘기면 아직 안 연 프로젝트(lazy)의 세션이 고아로 몰려 죽는다.
    static func orphans(sessions: [String], liveSessionNames: Set<String>,
                        knownProjectIds: Set<String>) -> [String] {
        sessions.filter { session in
            guard let parsed = parse(session) else { return false }
            guard knownProjectIds.contains(parsed.projectId) else { return false }
            return !liveSessionNames.contains(session)
        }
    }
}
