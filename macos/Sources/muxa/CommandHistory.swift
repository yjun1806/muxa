import Foundation

/// 실행된 명령 하나의 영속 이력 — "언제 마지막으로 돌렸나"를 기억한다.
///
/// 스크립트와 일회용을 하나로 합친 "명령" 모델의 근간이다. 등록 여부와 무관하게 **실행되면 기록**된다:
/// 등록 명령의 lastRun 표시도, 미등록(즉석) 명령의 히스토리도 이 한 목록에서 나온다. `command`가 신원
/// (같은 명령은 한 엔트리로 병합) — 표시 이름·cwd는 마지막 실행 기준으로 갱신된다.
struct CommandHistoryEntry: Codable, Equatable, Identifiable {
    /// 실행 명령 — 병합 신원. 같은 문자열이면 같은 엔트리로 본다.
    let command: String
    /// 표시 이름(등록 명령은 지정 이름, 즉석은 보통 명령 자체).
    var name: String
    /// 실행 폴더(없으면 프로젝트·워크스페이스 경로 상속).
    var cwd: String?
    /// 마지막 실행 시각 — "N분 전" 표시·최근순 정렬의 근거.
    var lastRunAt: Date
    /// 실행 횟수(누적).
    var runCount: Int

    var id: String { command }
}

/// 명령 이력을 다루는 **순수** 로직 — 병합·상한·섹션 분류. 파일 IO·실행은 경계가 맡는다.
enum CommandHistory {
    /// 이력 상한 — 최근 이만큼만 유지하고 오래된 것부터 버린다(무한정 쌓이지 않게).
    static let limit = 100

    /// 실행 1건을 이력에 합친다(순수). 같은 `command`면 최신으로 갱신하며 맨 앞(최근)으로 올리고,
    /// 없으면 새로 추가한다. 최근순을 유지하며 `limit`으로 자른다.
    static func record(_ entries: [CommandHistoryEntry],
                       command: String, name: String, cwd: String?, now: Date) -> [CommandHistoryEntry] {
        let prior = entries.first { $0.command == command }
        let entry = CommandHistoryEntry(command: command, name: name, cwd: cwd,
                                        lastRunAt: now, runCount: (prior?.runCount ?? 0) + 1)
        let rest = entries.filter { $0.command != command }
        return Array(([entry] + rest).prefix(limit))
    }

    /// 한 명령의 **현재 세션 실행 상태** — 그 `command`로 실행된 인스턴스(`oneOffScripts`) 중 가장 최근
    /// run(`startedAt` 기준). 없으면 nil = 이번 세션엔 안 돌린 과거 기록(뷰는 lastRun만 보여준다).
    /// 재시작하면 인스턴스가 사라져 자연히 nil이 된다(영속 이력만 남고 상태는 세션 한정).
    static func runState(command: String, instances: [LocatedScript],
                         runs: [String: ScriptRun]) -> ScriptRun? {
        instances.filter { $0.script.command == command }
            .compactMap { runs[$0.id] }
            .max(by: { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) })
    }

    /// 등록 명령 + 이력을 명령 탭의 두 섹션으로 가른다(순수).
    ///  - **등록 섹션**: `registered` 각각 + 이력에서 찾은 `lastRunAt`(한 번도 안 돌렸으면 nil).
    ///  - **히스토리 섹션**: 등록 안 된 명령만, 최근순(이력 순서 그대로).
    /// 등록한 명령은 등록 섹션에만 두고 히스토리에서 뺀다 — 한 명령이 두 섹션에 겹쳐 뜨지 않게.
    static func sections(registered: [Script], history: [CommandHistoryEntry])
        -> (registered: [(script: Script, lastRunAt: Date?)], history: [CommandHistoryEntry])
    {
        let registeredCommands = Set(registered.map(\.command))
        let lastRunByCommand = Dictionary(history.map { ($0.command, $0.lastRunAt) },
                                          uniquingKeysWith: { first, _ in first })
        let registeredSection = registered.map { (script: $0, lastRunAt: lastRunByCommand[$0.command]) }
        let historySection = history.filter { !registeredCommands.contains($0.command) }
        return (registeredSection, historySection)
    }
}
