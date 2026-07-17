import Foundation

/// 스크립트 = 프로젝트에 등록된 **끝이 있는 명령**(`make build`·`pnpm test` 등).
/// 서비스(Service.swift)와 반대 축이다 — 서비스는 끝이 없는 프로세스, 스크립트는 1회 돌고 끝난다.
///
/// 실행은 서비스와 **같은 tmux 백엔드**에 위임한다(탭을 띄우지 않는다 — 백그라운드 실행).
/// `remain-on-exit` 덕에 프로세스가 끝나도 pane이 남아 **exit code와 마지막 로그가 보존**되고,
/// 서비스 도크가 그 자리에서 보여준다(실행 중 = attach 터미널, 종료 = 읽기 전용 로그).
///
/// `ProjectScript`(ProjectScripts.swift)와 혼동 금지 — 그쪽은 package.json·Makefile·scripts/
/// **디렉터리 스캔 후보**(휘발, 목록 표시용)이고, 사용자가 **등록**하면 이 Script(영속,
/// `Project.scripts`에 실려 저장)로 승격된다.
struct Script: Codable, Identifiable, Equatable {
    let id: String
    var name: String // 표시 이름 ("build")
    var command: String // 실행 명령 ("make build")
}

/// 스크립트 하나 + **어디에 속하는가** — `LocatedService`와 같은 이유(도크는 창 전체를 본다).
struct LocatedScript: Identifiable {
    var id: String { script.id }
    let script: Script
    let workspaceId: String
    let workspaceName: String
    let projectId: String
    let projectName: String
    /// 실행 cwd — 프로젝트 자체 경로(워크트리)가 있으면 그것, 없으면 워크스페이스 경로 상속(서비스와 같은 규칙).
    let cwd: String?
}

/// 모든 워크스페이스·프로젝트의 스크립트를 소속과 함께 한 목록으로 편다(선언 순서 유지).
/// 모니터 폴링·도크 목록·고아 정리가 전부 이 순회 하나를 쓴다(collectAllServices와 같은 원칙).
func collectAllScripts(in workspaces: [Workspace]) -> [LocatedScript] {
    workspaces.flatMap { ws in
        ws.projects.flatMap { project in
            (project.scripts ?? []).map {
                LocatedScript(script: $0,
                              workspaceId: ws.id, workspaceName: ws.name,
                              projectId: project.id, projectName: project.name,
                              cwd: project.path ?? ws.path)
            }
        }
    }
}

/// 등록된 스크립트 id 전부 — 고아 정리(TmuxService.collectScriptGarbage)의 입력.
/// **활성 워크스페이스만 훑으면 안 된다**(collectLiveServiceIds와 같은 함정) — 반드시 전체를 훑는다.
func collectLiveScriptIds(in workspaces: [Workspace]) -> Set<String> {
    Set(workspaces.flatMap(\.projects).flatMap { $0.scripts ?? [] }.map(\.id))
}

/// 실행 1회의 상태(순수 값) — 푸터 칩·팝오버·도크가 관측한다.
///
/// **진실 원천은 tmux다**(ServiceMonitor 폴링) — 저장 키는 scriptId, 탭·서피스와 무관하다.
/// muxa가 재시작해도 tmux 세션은 살아 있으므로, 폴링이 다시 관측하면 레지스트리가 복원된다(채택).
struct ScriptRun: Equatable {
    enum RunState: Equatable {
        case running
        /// code nil = 결과 미상(세션이 관측 전에 사라짐 — 외부 kill·tmux 서버 사망).
        /// **성공으로 단정하지 않는다**(칩이 ✓를 지어내면 안 된다).
        /// duration nil = 걸린 시간 미상(재시작 후 채택 등) — 지어내지 않고 표기를 생략한다.
        case finished(code: Int32?, duration: TimeInterval?)
    }

    let scriptId: String
    /// 소속 프로젝트 — 푸터 칩(프로젝트 단위)이 전역 레지스트리에서 제 것만 거르는 키.
    let projectId: String
    let name: String
    /// nil = 시작 시각 미상(muxa 재시작 후 도는 세션을 채택한 경우) — 경과를 지어내지 않는다.
    var startedAt: Date?
    var state: RunState
    /// 잔류(✓/✗ 칩)를 사용자가 확인했다 — 칩은 내려가되 **레지스트리·세션·로그는 남는다**
    /// (종료 로그를 봐야 하므로 결과 확인이 곧 삭제면 안 된다).
    var acknowledged: Bool = false
}

// MARK: 표시 판정용 파생값(순수) — 칩(ScriptChipMode)·도크가 같은 정의를 쓴다

extension ScriptRun {
    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// 실패 **확정**(code 있고 ≠0)만 — code nil(결과 미상)은 실패로 단정하지 않는다
    /// (✓를 안 지어내는 것과 대칭으로, ✗도 안 지어낸다).
    var isFailure: Bool {
        if case .finished(let code, _) = state, let code, code != 0 { return true }
        return false
    }
}

// MARK: 전이 규칙(순수) — tmux 관측 1회를 레지스트리에 합친다

extension ScriptRun {
    /// 방금 시작한 실행이 폴 스냅샷에 아직 안 보여도 봐주는 유예 — `new-session`과 in-flight
    /// `list-panes`가 경합하면 한 바퀴(2s) 정도 관측이 늦는다. 이 유예가 없으면 merge가
    /// 갓 시작한 실행을 "세션 없음 = 결과 미상"으로 오판해 즉시 마감한다.
    static let missingGrace: TimeInterval = 10

    /// 폴링 관측 1회를 레지스트리에 합친다(순수). 반환은 (다음 레지스트리, 이번에 **새로 확정된 종료**).
    ///
    /// 규칙 — 어느 순서로 관측돼도 결과가 뒤집히지 않는다:
    ///  - 관측 .running: 레지스트리도 running이면 유지(startedAt 보존). 아니면 **채택** —
    ///    muxa 재시작 후 도는 세션. startedAt은 모른다(nil — 경과를 지어내지 않는다).
    ///  - 관측 .exited(code): running → finished(code) 확정 + exits에 실림(알림은 이 목록만).
    ///    이미 finished면 유지(첫 판정이 이긴다). 레지스트리에 없으면 **조용히 채택**(acknowledged) —
    ///    재시작 전의 결과를 재알림·재잔류시키지 않는다(ServiceMonitor baseline과 같은 원칙).
    ///  - 관측 없음(세션 소멸): running이던 것은 유예(missingGrace) 안이면 유지(막 시작 — 관측 지연),
    ///    지났으면 finished(code nil) — 결과 미상으로 마감하되 exits에는 안 싣는다(지어내지 않는다).
    ///    finished는 그대로 — 세션이 정리돼도 확정된 결과는 남는다.
    ///  - 등록이 사라진 스크립트의 run은 버린다(레지스트리는 등록의 그림자다).
    static func merging(runs: [String: ScriptRun],
                        observed: [String: ServiceState],
                        registered: [LocatedScript],
                        now: Date) -> (runs: [String: ScriptRun], exits: [ScriptRun]) {
        var next: [String: ScriptRun] = [:]
        var exits: [ScriptRun] = []
        for located in registered {
            let id = located.script.id
            let prev = runs[id]
            switch observed[id] {
            case .running:
                if let prev, prev.isRunning {
                    next[id] = prev
                } else {
                    next[id] = ScriptRun(scriptId: id, projectId: located.projectId,
                                         name: located.script.name, startedAt: nil, state: .running)
                }
            case .exited(let code):
                if let prev {
                    if prev.isRunning {
                        var done = prev
                        done.state = .finished(code: code,
                                               duration: prev.startedAt.map { now.timeIntervalSince($0) })
                        next[id] = done
                        exits.append(done)
                    } else {
                        next[id] = prev // 첫 판정 유지 — 같은 pane의 중복 관측이 결과를 못 뒤집는다
                    }
                } else {
                    next[id] = ScriptRun(scriptId: id, projectId: located.projectId,
                                         name: located.script.name, startedAt: nil,
                                         state: .finished(code: code, duration: nil),
                                         acknowledged: true)
                }
            case .missing, .none:
                guard let prev else { break }
                if prev.isRunning {
                    if let started = prev.startedAt, now.timeIntervalSince(started) < missingGrace {
                        next[id] = prev
                    } else {
                        var done = prev
                        done.state = .finished(code: nil,
                                               duration: prev.startedAt.map { now.timeIntervalSince($0) })
                        next[id] = done
                    }
                } else {
                    next[id] = prev
                }
            }
        }
        return (next, exits)
    }

    /// 새 실행이 시작될 때 같은 프로젝트의 잔류(finished) 칩을 내린다(순수) — 칩의 완료 잔류(✓/✗)는
    /// "가장 최근 일" 하나만 말하므로, 새 일이 시작되면 옛 결과는 확인된 것으로 친다.
    /// **지우지 않고 acknowledge만 한다** — 지우면 다음 폴링이 살아있는 pane을 다시 채택해 잔류가 되살아나고,
    /// 도크의 로그 진입점도 함께 사라진다.
    static func acknowledgingFinished(_ runs: [String: ScriptRun],
                                      projectId: String) -> [String: ScriptRun] {
        runs.mapValues { run in
            guard run.projectId == projectId, !run.isRunning else { return run }
            var next = run
            next.acknowledged = true
            return next
        }
    }
}
