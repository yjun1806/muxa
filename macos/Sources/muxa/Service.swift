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
    /// 실행 폴더 지정 — **nil이면 프로젝트 경로(없으면 워크스페이스 경로) 상속**. 모노레포의 하위
    /// 패키지(`apps/admin`)처럼 프로젝트 루트가 아닌 곳에서 돌 서비스를 위한 값. 기본값과 같은 입력은
    /// 저장하지 않는다(`runCwdOverride`) — 프로젝트 경로가 바뀔 때 얼어붙지 않게.
    /// 옵셔널이라 하위호환(옛 저장분엔 없음 → nil로 디코드).
    var cwd: String?
}

/// 서비스·스크립트 추가 시트의 실행 폴더 입력 → 저장할 지정값(순수). **nil = 상속**(프로젝트 경로).
///
/// `~`는 홈으로 편다 — tmux `new-session -c`는 셸을 안 거치므로 틸드를 모른다. 뒤 슬래시를 정리한 뒤
/// **기본값과 같으면 nil을 돌려준다** — 같은 값을 저장해두면 프로젝트 경로가 바뀔 때(워크트리 이동 등)
/// 이 서비스만 옛 경로에 얼어붙는다. 지정은 "다를 때만" 저장한다.
func runCwdOverride(entered: String, defaultCwd: String?, home: String) -> String? {
    let trimmed = entered.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    let expanded: String
    if trimmed == "~" {
        expanded = home
    } else if trimmed.hasPrefix("~/") {
        expanded = home + trimmed.dropFirst(1)
    } else {
        expanded = trimmed
    }
    let normalized = normalizePath(expanded)
    return normalized == defaultCwd.map(normalizePath) ? nil : normalized
}

/// 모든 워크스페이스·프로젝트에 등록된 서비스 id 전부. 고아 정리(TmuxService.collectGarbage)의 입력이다.
///
/// **활성 워크스페이스만 훑으면 안 된다.** 다른 워크스페이스의 서비스가 '등록 없음'으로 몰려 고아로
/// 판정되고, 멀쩡히 돌던 dev 서버가 죽는다. 반드시 전체를 훑는다.
func collectLiveServiceIds(in workspaces: [Workspace]) -> Set<String> {
    Set(workspaces.flatMap(\.projects).flatMap { $0.services ?? [] }.map(\.id))
}

/// 이 인스턴스가 아는 프로젝트 id 전부. 고아 정리의 **판정 범위**다 — 여기 없는 프로젝트의 세션은
/// 다른 muxa 인스턴스의 것으로 보고 건드리지 않는다(ServiceSession.orphans 주석 참조).
func collectKnownProjectIds(in workspaces: [Workspace]) -> Set<String> {
    Set(workspaces.flatMap(\.projects).map(\.id))
}

/// 서비스 하나 + **어디에 속하는가**(워크스페이스·프로젝트).
///
/// 서비스는 프로젝트 소속이지만, 사용자가 알아야 하는 건 "지금 이 프로젝트"가 아니라
/// **창 전체에서 뭐가 도는가**다. 다른 워크스페이스의 dev 서버가 죽었는데 거기 들어가야만
/// 알 수 있다면 알림으로서 실패다.
struct LocatedService: Identifiable {
    var id: String { service.id }
    let service: Service
    let workspaceId: String
    let workspaceName: String
    let projectId: String
    let projectName: String
    /// 이 서비스가 도는 폴더 — 도크가 **활성 프로젝트 전환 없이** 그 자리에서 로그/터미널을 열 때 쓴다.
    /// 해석 사슬: 서비스 자체 지정(`Service.cwd`) → 프로젝트 자체 경로(워크트리) → 워크스페이스 경로.
    /// 시작·재시작·attach가 전부 이 값 하나를 쓴다(규칙이 갈라지면 "로그는 여기, 실행은 저기"가 된다).
    let cwd: String?
}

/// 모든 워크스페이스·프로젝트의 서비스를 소속과 함께 한 목록으로 편다(선언 순서 유지).
func collectAllServices(in workspaces: [Workspace]) -> [LocatedService] {
    workspaces.flatMap { ws in
        ws.projects.flatMap { project in
            (project.services ?? []).map {
                LocatedService(service: $0,
                               workspaceId: ws.id, workspaceName: ws.name,
                               projectId: project.id, projectName: project.name,
                               cwd: $0.cwd ?? project.path ?? ws.path)
            }
        }
    }
}

/// 이 id의 서비스를 소속과 함께 찾는다(순수). 없으면 nil.
///
/// **인박스 라우팅이 이걸 쓴다.** 서비스가 죽으면 `tabId`에 **서비스 id**를 담아 기록하는데,
/// 서비스는 탭 트리 밖에 살아(D19) 그 id로는 어떤 탭도 못 찾는다. 탭으로 착각한 채 진행하면
/// 프로젝트만 이동하고 Git 패널이 열려, **죽은 서버의 사인을 보러 가는 유일한 동선이 엉뚱한 패널을
/// 연다.** 라우팅 전에 "이건 서비스인가"를 여기서 먼저 묻는다.
func locateService(_ serviceId: String, in workspaces: [Workspace]) -> LocatedService? {
    collectAllServices(in: workspaces).first { $0.id == serviceId }
}

/// 프로젝트 하나에 묶인 서비스·스크립트 — 도크가 프로젝트별로 나눠 보여주는 단위.
/// 두 축이 한 그룹에 사는 이유: 도크는 "이 프로젝트에서 도는(돌았던) 것"의 단일 목록이다 —
/// 서비스만 그룹을 만들면 스크립트뿐인 프로젝트·워크스페이스가 목록에서 통째로 사라진다.
struct ServiceGroup: Identifiable {
    var id: String { projectId }
    let projectId: String
    /// 사람이 읽을 묶음 이름 — 워크스페이스가 여럿이면 어느 워크스페이스인지도 밝힌다("front › 웹").
    let title: String
    let services: [LocatedService]
    let scripts: [LocatedScript]
}

/// 서비스·스크립트를 프로젝트별로 묶는다 — **현재 프로젝트가 맨 앞**, 나머지는 선언 순서 그대로
/// (서비스가 먼저 나온 프로젝트 순, 스크립트뿐인 프로젝트는 그 뒤). 순수.
///
/// 정렬로 앞에 세우면 안 된다. `sorted { a, _ in a == current }`는 엄격 약순서가 아니라
/// (a<b와 b<a가 동시에 거짓/참일 수 있다) 정렬 알고리즘이 비교자를 어떻게 호출하느냐에 따라
/// **현재 프로젝트가 맨 앞에 안 오는 배치가 나온다.** 분할(filter 두 번)은 그 자체로 결정적이다.
func groupServices(_ items: [LocatedService], scripts: [LocatedScript] = [],
                   current: String, showWorkspace: Bool) -> [ServiceGroup] {
    var order: [String] = []
    var byProject: [String: [LocatedService]] = [:]
    var scriptsByProject: [String: [LocatedScript]] = [:]
    for item in items {
        if byProject[item.projectId] == nil { order.append(item.projectId) }
        byProject[item.projectId, default: []].append(item)
    }
    for item in scripts {
        if byProject[item.projectId] == nil, scriptsByProject[item.projectId] == nil {
            order.append(item.projectId)
        }
        scriptsByProject[item.projectId, default: []].append(item)
    }
    return (order.filter { $0 == current } + order.filter { $0 != current })
        .compactMap { pid in
            let group = byProject[pid] ?? []
            let scriptGroup = scriptsByProject[pid] ?? []
            // 이름은 어느 쪽이든 첫 항목에서 얻는다 — 둘 다 비면 그룹 자체가 없다.
            guard let title = group.first.map({ showWorkspace ? "\($0.workspaceName) › \($0.projectName)" : $0.projectName })
                ?? scriptGroup.first.map({ showWorkspace ? "\($0.workspaceName) › \($0.projectName)" : $0.projectName })
            else { return nil }
            return ServiceGroup(projectId: pid, title: title, services: group, scripts: scriptGroup)
        }
}

/// 한 워크스페이스에 속한 서비스 묶음 — 팝오버가 "현재 vs 다른 워크스페이스"를 가르는 단위.
/// 워크스페이스가 컨테이너, 그 안이 프로젝트 그룹(`ServiceGroup`)이다(사이드바 2단 트리와 같은 위계).
struct ServiceScope: Identifiable {
    var id: String { workspaceId }
    let workspaceId: String
    let workspaceName: String
    let isCurrent: Bool
    let groups: [ServiceGroup]
    /// 이 워크스페이스의 항목(서비스+스크립트) 총 개수 — 접힌 줄이 "⚠ 3"처럼 요약할 때 쓴다.
    var serviceCount: Int { groups.reduce(0) { $0 + $1.services.count + $1.scripts.count } }
    /// 접힌 줄의 롤업 대상 — 모든 서비스를 편평하게(상태는 뷰가 monitor로 채운다).
    var allServices: [LocatedService] { groups.flatMap(\.services) }
    /// 접힌 줄의 롤업 대상(스크립트 축) — 실패한 실행이 접힌 워크스페이스에 묻히지 않게.
    var allScripts: [LocatedScript] { groups.flatMap(\.scripts) }
}

/// 서비스·스크립트를 **워크스페이스**로 묶는다 — 현재 워크스페이스가 맨 앞, 그 안은 `groupServices`
/// 규칙(현재 프로젝트 먼저). 순수. 정렬이 아니라 분할(filter 두 번)을 쓰는 이유는 `groupServices`와 같다.
func groupByWorkspace(_ items: [LocatedService], scripts: [LocatedScript] = [],
                      currentWorkspaceId: String, currentProjectId: String) -> [ServiceScope] {
    var order: [String] = []
    var byWorkspace: [String: [LocatedService]] = [:]
    var scriptsByWorkspace: [String: [LocatedScript]] = [:]
    for item in items {
        if byWorkspace[item.workspaceId] == nil { order.append(item.workspaceId) }
        byWorkspace[item.workspaceId, default: []].append(item)
    }
    for item in scripts {
        if byWorkspace[item.workspaceId] == nil, scriptsByWorkspace[item.workspaceId] == nil {
            order.append(item.workspaceId)
        }
        scriptsByWorkspace[item.workspaceId, default: []].append(item)
    }
    return (order.filter { $0 == currentWorkspaceId } + order.filter { $0 != currentWorkspaceId })
        .compactMap { wsId in
            let group = byWorkspace[wsId] ?? []
            let scriptGroup = scriptsByWorkspace[wsId] ?? []
            guard let name = group.first?.workspaceName ?? scriptGroup.first?.workspaceName else { return nil }
            // 워크스페이스 이름은 스코프 헤더가 말하므로 프로젝트 그룹은 showWorkspace=false.
            return ServiceScope(workspaceId: wsId, workspaceName: name,
                                isCurrent: wsId == currentWorkspaceId,
                                groups: groupServices(group, scripts: scriptGroup,
                                                      current: currentProjectId, showWorkspace: false))
        }
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

extension ServiceState {
    /// **비정상 종료인가** — 사용자에게 알릴 가치가 있는 죽음.
    ///
    /// 이 판정("정상 종료(0)는 죽음으로 치지 않는다")은 알림·배지·요약·도크 강조가 전부 공유하는
    /// 하나의 결정이다. 각자 `if case .exited(let c) = … { c != 0 }`를 다시 쓰면 한 곳만 고쳐졌을 때
    /// 배지는 뜨는데 알림은 안 오는 식으로 갈라진다.
    var isFailure: Bool {
        if case .exited(let code) = self { return code != 0 }
        return false
    }
}

/// 서비스 ↔ tmux 세션 사이의 순수 로직 — 세션명 규약·출력 파싱·고아 판정·포트 추출.
/// 부작용(셸아웃)은 `TmuxService` 경계에만 두고 여기는 전부 순수 함수로 유지한다.
enum ServiceSession {
    /// 세션명 규약: `muxa__<projectId>__<serviceId>`.
    /// 접두사는 소유권 표식이다 — 이게 없는 세션은 파싱도 정리도 하지 않는다(남의 tmux 작업 보호).
    /// 구분자가 `__`인 이유: id로 쓰는 UUID에는 하이픈은 있어도 언더스코어가 없어 충돌하지 않는다.
    static let prefix = "muxa"
    static let separator = "__"

    /// 세션명에 쓸 수 있는 id인가 — `[A-Za-z0-9-]+`(우리가 만드는 id는 UUID라 항상 통과한다).
    ///
    /// **id는 신뢰 경계 밖이다.** state.v4.json은 사용자·외부가 쓸 수 있고 muxa는 적대적 리포를 여는 게
    /// 본업이다. 검증이 없으면 두 가지가 샌다:
    ///  1. `'`가 든 id → attach 명령(유일하게 셸을 거치는 경로)에서 따옴표를 조기에 닫아 임의 명령 실행.
    ///     인용(`ShellQuote.single`)이 1차 방어선이고, 이 화이트리스트가 2차다.
    ///  2. `__`가 든 id → `parse`가 4토막이라 nil을 내놓는데 세션은 만들어져, 상태도 정리도 안 되는
    ///     **조용한 좀비**가 남는다(고아 판정이 못 보므로 영원히).
    static func isValidId(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// 세션명. **id가 규약을 벗어나면 이름을 만들지 않는다** — 세션을 만들지 못하는 편이,
    /// 손댈 수 없는 좀비를 만드는 것보다 낫다(호출부가 nil을 사용자에게 알린다).
    static func name(projectId: String, serviceId: String) -> String? {
        guard isValidId(projectId), isValidId(serviceId) else { return nil }
        return [prefix, projectId, serviceId].joined(separator: separator)
    }

    /// muxa 소유 세션명만 (projectId, serviceId)로 분해한다. 아니면 nil.
    static func parse(_ sessionName: String) -> (projectId: String, serviceId: String)? {
        let parts = sessionName.components(separatedBy: separator)
        guard parts.count == 3, parts[0] == prefix,
              !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (parts[1], parts[2])
    }

    /// `tmux list-panes -a -F '#{session_name}|#{pane_index}|#{pane_dead}|#{pane_dead_status}'` 출력 → 세션별 상태.
    /// 형식이 어긋난 줄은 조용히 버린다(상태를 지어내지 않는다).
    ///
    /// **pane 0만 세션의 상태다.** 사용자가 attach해서 화면을 나누면 한 세션에 pane이 여럿 생기는데,
    /// 전부 받아들이면 마지막으로 읽은 줄이 이겨(딕셔너리 덮어쓰기) 상태가 비결정적이 된다 —
    /// 서비스 프로세스가 죽었는데 옆 pane의 셸이 살아 있다고 `.running`으로 보이는 식이다.
    /// 서비스 명령은 항상 `new-session`이 만든 pane 0에서 돈다.
    static func parsePanes(_ raw: String) -> [String: ServiceState] {
        var states: [String: ServiceState] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 4, !fields[0].isEmpty, fields[1] == "0" else { continue }
            let session = fields[0]
            if fields[2] == "1" {
                // 죽었다. status가 비면(신호 종료 등) 코드는 모르지만 죽었다는 사실은 확정이다.
                states[session] = .exited(code: Int32(fields[3]) ?? -1)
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
    /// **죽이는 건 우리가 확실히 아는 것만.** 파괴적 동작이라 판정은 좁게, 보존은 넓게 잡는다.
    /// 보존(=건드리지 않음) 조건 — 하나라도 참이면 남긴다:
    ///  1) muxa 소유 세션이 아님 — 사용자의 다른 tmux 작업은 절대 죽이지 않는다(전용 소켓이라 원래
    ///     섞일 일이 없지만, 파괴적 동작이므로 판정에서 한 번 더 막는다)
    ///  2) **내가 모르는 프로젝트의 세션** — muxa 인스턴스는 여럿 떠 있을 수 있고(창 여러 개, 개발용
    ///     워크트리 빌드) 같은 tmux 소켓을 공유한다. 내 state에 없는 프로젝트의 세션은 남의 것이다.
    ///     이 가드가 없으면 인스턴스끼리 서로의 dev 서버를 몰살한다.
    ///     따라서 아는 프로젝트가 하나도 없으면(knownProjectIds가 비면) 아무것도 지우지 않는다.
    ///  3) 등록된 서비스에 대응함(serviceId ∈ liveServiceIds)
    static func orphans(sessions: [String], liveServiceIds: Set<String>,
                        knownProjectIds: Set<String>) -> [String] {
        sessions.filter { session in
            guard let parsed = parse(session) else { return false }
            guard knownProjectIds.contains(parsed.projectId) else { return false }
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
