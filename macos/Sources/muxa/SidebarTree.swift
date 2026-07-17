import Foundation

/// 사이드바 2단 트리(워크스페이스 › 프로젝트)의 **순수 판정** — 펼침 규칙·상태 신호·주의 큐 대상.
///
/// 뷰도 AppState도 이 규칙을 재구현하지 않는다. 부작용이 0이라 앱을 띄우지 않고 테스트로 못 박는다
/// (`StateLoad`와 같은 급의 순수 enum).
enum SidebarTree {
    /// 프로젝트 행이 말하는 것 — 폴더가 아니라 "그 안의 에이전트가 지금 뭘 하고 있나".
    /// 색이 아니라 **모양(점 크기)**으로도 구분된다 → `ProjectStatusStyle`.
    enum ProjectStatus: Equatable {
        case idle, working, attention
    }

    /// 판정 입력 스냅샷(순수 값) — 경계(AppState)가 모아서 넘긴다.
    struct ProjectSignal: Equatable {
        /// 안 보는 동안 쌓인 주의(`AppState.badgedProjects` — 배지의 진실 원천).
        var isBadged = false
        /// 지금 이 프로젝트의 칸 하나라도 입력 대기.
        /// **활성 프로젝트엔 배지가 안 붙으므로** 보고 있는 프로젝트의 주의는 이 신호로만 잡힌다.
        var isWaiting = false
        /// 칸 하나라도 작업 중.
        var isWorking = false
        /// dev 서버가 비정상 종료했다 — 그것도 사람을 기다리는 상태다.
        var hasDeadService = false
    }

    /// 우선순위: 주의 > 작업중 > 유휴. **의심되면 주의 쪽으로 올린다**(놓친 주의의 비용 > 헛점 하나의 비용).
    static func status(_ signal: ProjectSignal) -> ProjectStatus {
        if signal.isBadged || signal.isWaiting || signal.hasDeadService { return .attention }
        if signal.isWorking { return .working }
        return .idle
    }

    /// 워크스페이스 롤업 — 자식 중 **가장 센 신호**가 그룹의 신호다(접힌 그룹·icon·slim이 쓴다).
    static func rollup(_ children: [ProjectStatus]) -> ProjectStatus {
        if children.contains(.attention) { return .attention }
        if children.contains(.working) { return .working }
        return .idle
    }

    // MARK: 펼침 (각 워크스페이스가 독립적으로 여닫힌다 — 집합이 유일한 진실)

    /// 이 워크스페이스가 지금 펼쳐져 있는가. **집합에 있으면 펼침** — 활성 여부와 무관하다.
    /// (활성은 로드·전환·생성 시 집합에 넣어 두므로, 여기서 특례를 둘 필요가 없다.)
    static func isExpanded(wsId: String, expanded: Set<String>) -> Bool {
        expanded.contains(wsId)
    }

    /// 디스클로저 클릭 — 그 워크스페이스 하나만 넣고/빼기. **다른 워크스페이스는 건드리지 않는다**
    /// (아코디언이 아니다 — 여럿이 동시에 펼쳐진 채 유지된다).
    static func toggled(_ expanded: Set<String>, wsId: String) -> Set<String> {
        var next = expanded
        if next.contains(wsId) { next.remove(wsId) } else { next.insert(wsId) }
        return next
    }

    /// 영속값 → 런타임 집합. **활성은 항상 펼친 채로 시작**한다(포커스한 워크스페이스는 프로젝트가 보여야
    /// 하고, 구 저장분엔 활성이 집합에 없으므로 마이그레이션도 여기서 겸한다). nil이면 활성만.
    static func restore(saved: [String]?, activeId: String, workspaceIds: [String]) -> Set<String> {
        var set = Set(saved ?? [])
        if !activeId.isEmpty { set.insert(activeId) }
        return prune(set, workspaceIds: workspaceIds)
    }

    /// 존재하지 않는 워크스페이스 id 제거 — 워크스페이스를 닫을 때 유령 id가 쌓이지 않게.
    static func prune(_ expanded: Set<String>, workspaceIds: [String]) -> Set<String> {
        expanded.intersection(workspaceIds)
    }

    // MARK: 주의 큐 (트리 맨 위 카드)

    /// 큐 카드 한 행이 가리키는 "나를 기다리는 프로젝트" — 워크스페이스 **이름**까지 실어
    /// "어느 워크스페이스의 메인인가"를 행이 말할 수 있게 한다(id만 주면 뷰가 조회를 재구현한다).
    struct WaitingRef: Equatable {
        let workspaceId: String
        let workspaceName: String
        let projectId: String
        let projectName: String
    }

    /// 배지 있는 프로젝트 **전부**를 순서대로 — 큐 카드의 행 목록.
    /// 순회 순서는 `AppState.waitingSlots`와 같다(워크스페이스 선언 순 → 프로젝트 선언 순) —
    /// 카드가 나열하는 곳과 ⌘⇧A가 가는 곳이 어긋나지 않게.
    static func allWaiting(workspaces: [Workspace], badged: Set<String>) -> [WaitingRef] {
        workspaces.flatMap { ws in
            ws.projects.filter { badged.contains($0.id) }.map {
                WaitingRef(workspaceId: ws.id, workspaceName: ws.name,
                           projectId: $0.id, projectName: $0.name)
            }
        }
    }

    /// 첫 대기 프로젝트 — ⌘⇧A 폴백(`jumpToNextWaiting`)이 쓴다.
    static func firstWaiting(workspaces: [Workspace], badged: Set<String>) -> WaitingRef? {
        allWaiting(workspaces: workspaces, badged: badged).first
    }
}
