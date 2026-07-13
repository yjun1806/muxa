import Foundation
import Observation

/// 서비스 상태 관측 — **접혀 있어도(서피스 렌더 없이) 돈다.** 진실 원천은 tmux다.
///
/// 폴링이 하나뿐인 이유: `list-panes -a`가 모든 세션의 상태를 한 번에 준다. 프로젝트마다 스토어를
/// 두면 같은 명령을 N번 돌리게 되므로, 앱 전체에 모니터 하나를 두고 서비스 id로 색인한다.
@Observable
@MainActor
final class ServiceMonitor {
    /// serviceId → 상태. 등록됐지만 tmux에 없으면 키가 없다(= .missing).
    private(set) var states: [String: ServiceState] = [:]
    /// serviceId → 리슨 포트. 한 번 찾으면 캐시한다(매번 capture-pane 하지 않게).
    private(set) var ports: [String: Int] = [:]

    /// 서비스가 죽었을 때 부른다(running → exited 전이 순간 1회). 알림·배지 배선은 AppState가 소유.
    var onExit: ((Service, Int32) -> Void)?

    /// 폴링 주기. 로그를 스트리밍하는 게 아니라 상태 점을 갱신하는 용도라 2초면 충분하다
    /// (사람이 "죽었네"를 알아채는 데 필요한 지연이지, 실시간성이 필요한 값이 아니다).
    static let pollInterval: Duration = .seconds(2)

    private var task: Task<Void, Never>?

    /// 등록된 서비스 전체(모든 워크스페이스)를 넘겨 폴링을 시작·갱신한다.
    /// 서비스가 하나도 없으면 폴링을 멈춘다 — 아무도 안 쓰는 기능이 2초마다 프로세스를 띄우지 않게.
    func sync(services: [Service]) {
        task?.cancel()
        guard TmuxService.isAvailable, !services.isEmpty else {
            task = nil
            states = [:]
            ports = [:]
            return
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(services: services)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 한 번 훑는다 — 상태 갱신 + 죽음 전이 감지 + (아직 모르는) 포트 조회.
    func refresh(services: [Service]) async {
        let byId = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        let bySession = await TmuxService.states()

        // 세션명 키 → 서비스 id 키로 옮긴다. muxa 소유가 아닌 세션은 parse가 걸러낸다.
        var next: [String: ServiceState] = [:]
        for (session, state) in bySession {
            guard let parsed = ServiceSession.parse(session), byId[parsed.serviceId] != nil else { continue }
            next[parsed.serviceId] = state
        }

        // 죽음 전이(running → exited)만 알린다. 이미 죽어 있던 걸 매 폴링마다 다시 알리면 인박스가 부푼다.
        for (id, state) in next {
            guard case .exited(let code) = state, let service = byId[id] else { continue }
            if case .running = states[id] ?? .missing {
                onExit?(service, code)
            }
        }

        states = next
        ports = ports.filter { next[$0.key] != nil } // 등록이 사라진 서비스의 포트 캐시 정리

        // 포트는 아직 모르는 running 서비스만 조회한다(capture-pane은 세션마다 프로세스를 띄우므로 아낀다).
        for (id, state) in next where state == .running && ports[id] == nil {
            guard let service = byId[id],
                  let projectId = await projectId(of: service, in: bySession) else { continue }
            let log = await TmuxService.capture(projectId: projectId, serviceId: id, lines: 60)
            if let port = ServiceSession.extractPort(log) { ports[id] = port }
        }
    }

    /// 세션명에서 프로젝트 id를 되찾는다(서비스 값 타입은 자기 프로젝트를 모른다 — 소유는 Project에 있다).
    private func projectId(of service: Service, in sessions: [String: ServiceState]) async -> String? {
        for session in sessions.keys {
            if let parsed = ServiceSession.parse(session), parsed.serviceId == service.id {
                return parsed.projectId
            }
        }
        return nil
    }
}
