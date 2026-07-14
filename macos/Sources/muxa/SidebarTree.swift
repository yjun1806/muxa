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

    // MARK: 펼침 (활성은 항상 펼침 — 규칙을 여기 한 곳에서만 강제한다)

    /// 이 워크스페이스가 지금 펼쳐져 있는가. **활성은 집합에 없어도 펼쳐진다**(접히지 않는다).
    static func isExpanded(wsId: String, activeId: String, expanded: Set<String>) -> Bool {
        wsId == activeId || expanded.contains(wsId)
    }

    /// 디스클로저 클릭. 활성 워크스페이스면 **무동작**(같은 집합을 그대로 돌려준다) — 접을 수 없기 때문.
    static func toggled(_ expanded: Set<String>, wsId: String, activeId: String) -> Set<String> {
        guard wsId != activeId else { return expanded }
        var next = expanded
        if next.contains(wsId) { next.remove(wsId) } else { next.insert(wsId) }
        return next
    }

    /// 영속값 → 런타임 집합. nil(구 저장분·최초 실행)이면 **빈 집합** = 활성만 펼침(마이그레이션 기본값).
    static func restore(saved: [String]?, workspaceIds: [String]) -> Set<String> {
        prune(Set(saved ?? []), workspaceIds: workspaceIds)
    }

    /// 존재하지 않는 워크스페이스 id 제거 — 워크스페이스를 닫을 때 유령 id가 쌓이지 않게.
    static func prune(_ expanded: Set<String>, workspaceIds: [String]) -> Set<String> {
        expanded.intersection(workspaceIds)
    }

    // MARK: 주의 큐 (트리 맨 위 한 줄)

    /// 큐 헤더가 가리킬 "지금 나를 기다리는 첫 프로젝트".
    struct WaitingRef: Equatable {
        let workspaceId: String
        let projectId: String
        let projectName: String
    }

    /// 순회 순서는 `AppState.waitingSlots`와 같다(워크스페이스 선언 순 → 프로젝트 선언 순) —
    /// 헤더가 가리키는 곳과 ⌘⇧A가 가는 곳이 어긋나지 않게.
    static func firstWaiting(workspaces: [Workspace], badged: Set<String>) -> WaitingRef? {
        for ws in workspaces {
            for project in ws.projects where badged.contains(project.id) {
                return WaitingRef(workspaceId: ws.id, projectId: project.id, projectName: project.name)
            }
        }
        return nil
    }
}
