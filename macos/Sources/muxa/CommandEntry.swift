import Foundation

/// 명령 하나 — 실행 후 즐겨찾기로 "등록"되는 통합 모델(구 `Script`+`CommandHistoryEntry` 대체).
///
/// 요구: (2) 등록 개념 대신 **실행 → ★즐겨찾기**(favorite=곧 등록) · (3) 명령 종류 무관(서비스성도 실행) ·
/// (4) 명령당 **실행 내역**을 로그와 함께 보관(최근 10개) · (5) 실행 경로(cwd)를 명령에 매어 둔다.
/// `command`가 신원 — 같은 명령은 한 엔트리로 묶이고, 실행할 때마다 `executions`에 한 줄 쌓인다.
struct CommandEntry: Codable, Equatable, Identifiable {
    /// 실행 명령 — 병합 신원.
    let command: String
    /// 즐겨찾기 표시 이름(선택). nil이면 명령 자체를 보인다.
    var name: String?
    /// 실행 경로 — nil이면 프로젝트(없으면 워크스페이스) 경로 상속.
    var cwd: String?
    /// **즐겨찾기 = 등록**. 켜면 즐겨찾기 섹션에 상시 노출, 끄면 히스토리로 내려간다.
    var favorite: Bool
    /// 실행 내역 — 최근이 앞. 명령당 `execLimit`개까지, 초과분은 오래된 것부터 버린다(로그도 함께).
    var executions: [CommandExecution]

    var id: String { command }
    /// 마지막 실행 시각 — 히스토리 정렬·"N분 전"의 근거.
    var lastRunAt: Date? { executions.first?.startedAt }
    /// 실행 횟수(보관된 내역 기준 — 상한에 잘리면 실제보다 작을 수 있다).
    var runCount: Int { executions.count }
}

/// 실행 1회의 영속 기록 — 시각·결과·소요시간. 출력 로그는 `id` 기반 별도 파일(용량 격리).
/// `id`는 실행 인스턴스(`scriptRuns`)·로그 파일과 잇는 키다(`launchScript`가 생성).
struct CommandExecution: Codable, Equatable, Identifiable {
    let id: String
    let startedAt: Date
    /// 종료 코드 — nil이면 아직 실행 중이거나 결과 미상(외부 kill·세션 소멸). 0=성공.
    var exitCode: Int?
    /// 소요 시간 — nil이면 미상(시작 시각을 모르거나 아직 안 끝남).
    var duration: TimeInterval?

    var isFinished: Bool { exitCode != nil }
    /// 실패 **확정**(code 있고 ≠0)만 — 미상(nil)은 실패로 단정하지 않는다.
    var isFailure: Bool { (exitCode ?? 0) != 0 && exitCode != nil }
}

/// 파일에서 발견한 프로젝트 스크립트 하나(package.json/Makefile/scripts) — 실행 준비된 명령.
/// `ProjectScript`(파싱 원본)를 명령 탭이 쓰기 좋은 형태로 정규화한 값. `command`는 실제 실행 명령이다.
struct DiscoveredScript: Equatable, Identifiable {
    let name: String    // "dev"
    let command: String // 실행 명령 "pnpm run dev" · "make dev"
    let source: String  // "package.json" · "Makefile" · "scripts/"
    var id: String { command }
}

/// 명령 목록을 다루는 **순수** 로직 — 실행 기록·즐겨찾기·cwd·섹션 분류·상한. 파일 IO(로그)는 경계가 맡는다.
enum CommandStore {
    /// 명령당 실행 내역 상한 — 초과분(오래된 실행)은 버린다. 로그 총량을 명령당으로 직접 제어한다.
    static let execLimit = 10

    /// 실행 **시작**을 기록한다(순수). 같은 `command` 엔트리에 실행을 얹고(없으면 새로 만든다),
    /// `cwd`를 이번 실행 값으로 갱신한다. 상한 초과로 밀려난 실행 id는 `dropped`로 돌려준다
    /// (경계가 그 로그 파일을 지운다). favorite·name은 보존한다(등록 상태는 실행이 안 건드린다).
    static func recordStart(_ entries: [CommandEntry], command: String, cwd: String?, name: String?,
                            execId: String, now: Date) -> (entries: [CommandEntry], dropped: [String]) {
        let exec = CommandExecution(id: execId, startedAt: now, exitCode: nil, duration: nil)
        var dropped: [String] = []
        var next = entries
        if let index = next.firstIndex(where: { $0.command == command }) {
            var entry = next[index]
            if let cwd { entry.cwd = cwd }
            var execs = [exec] + entry.executions
            if execs.count > execLimit {
                dropped = execs[execLimit...].map(\.id)
                execs = Array(execs.prefix(execLimit))
            }
            entry.executions = execs
            next[index] = entry
        } else {
            next.append(CommandEntry(command: command, name: name, cwd: cwd,
                                     favorite: false, executions: [exec]))
        }
        return (next, dropped)
    }

    /// 실행 **완료**를 반영한다(순수) — `execId`를 가진 실행에 종료 코드·소요시간을 채운다.
    static func recordFinish(_ entries: [CommandEntry], execId: String,
                             exitCode: Int?, duration: TimeInterval?) -> [CommandEntry] {
        entries.map { entry in
            guard entry.executions.contains(where: { $0.id == execId }) else { return entry }
            var next = entry
            next.executions = entry.executions.map { exec in
                guard exec.id == execId else { return exec }
                var e = exec
                e.exitCode = exitCode
                e.duration = duration
                return e
            }
            return next
        }
    }

    /// 즐겨찾기 토글(순수) — 켜면 즐겨찾기, 끄면 내림. 아직 실행 안 한 **발견 스크립트를 ☆** 하면
    /// 엔트리가 없으므로 즐겨찾기(executions 없음)로 **새로 만든다**.
    static func toggleFavorite(_ entries: [CommandEntry], command: String,
                               name: String? = nil, cwd: String? = nil) -> [CommandEntry] {
        if entries.contains(where: { $0.command == command }) {
            return entries.map { $0.command == command ? { var e = $0; e.favorite.toggle(); return e }($0) : $0 }
        }
        return entries + [CommandEntry(command: command, name: name, cwd: cwd, favorite: true, executions: [])]
    }

    /// 명령의 실행 경로를 바꾼다(순수).
    static func setCwd(_ entries: [CommandEntry], command: String, cwd: String?) -> [CommandEntry] {
        entries.map { $0.command == command ? { var e = $0; e.cwd = cwd; return e }($0) : $0 }
    }

    /// 명령 하나를 지운다(순수) — 버려진 실행 id 전부를 `dropped`로(경계가 로그 삭제).
    static func remove(_ entries: [CommandEntry], command: String) -> (entries: [CommandEntry], dropped: [String]) {
        let dropped = entries.first { $0.command == command }?.executions.map(\.id) ?? []
        return (entries.filter { $0.command != command }, dropped)
    }

    /// 명령 탭의 두 섹션(순수) — **즐겨찾기**(favorite, 이름·명령 순 안정) / **히스토리**(비favorite, 최근 실행순).
    static func sections(_ entries: [CommandEntry]) -> (favorites: [CommandEntry], history: [CommandEntry]) {
        let favorites = entries.filter(\.favorite)
        let history = entries.filter { !$0.favorite }
            .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
        return (favorites, history)
    }

    /// 명령 탭의 **세 덩어리**(순수) — 발견 스크립트를 포함한다:
    ///  - **favorites**: `favorite`인 명령(발견·즉석 무관). 상단 고정.
    ///  - **projectScripts**: package.json/Makefile 발견분 중 **즐겨찾기 아닌 것**. 파일이 진실이라 항상
    ///    노출되는 **실행 카탈로그**(실행했든 안 했든).
    ///  - **history**: **실행 이력이 있는** 비즐겨찾기 명령 전부(발견분 포함) — 각 실행의 내역을 본다.
    ///    발견 스크립트를 실행하면 카탈로그(위)엔 상시, 여기(아래)엔 그 실행 내역이 함께 뜬다(역할이 다르다).
    static func panelSections(_ entries: [CommandEntry], discovered: [DiscoveredScript])
        -> (favorites: [CommandEntry], projectScripts: [DiscoveredScript], history: [CommandEntry])
    {
        let favorites = entries.filter(\.favorite)
        let favoriteCommands = Set(favorites.map(\.command))
        let scripts = discovered.filter { !favoriteCommands.contains($0.command) }
        let history = entries
            .filter { !$0.favorite && !$0.executions.isEmpty }
            .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
        return (favorites, scripts, history)
    }

    /// v1(등록 `scripts` + `commandHistory`) → v2 `commands` 이관(순수). 둘 다 비면 nil(이관 불필요).
    /// **등록 스크립트 = favorite**(이름 보존), 히스토리 = 비favorite(lastRunAt을 실행 하나로 심는다 —
    /// 과거 로그는 없으니 결과 미상). 같은 명령은 한 엔트리로 묶고, 등록이면 favorite을 켠다.
    static func migrate(scripts: [Script], history: [CommandHistoryEntry]) -> [CommandEntry]? {
        if scripts.isEmpty && history.isEmpty { return nil }
        var byCommand: [String: CommandEntry] = [:]
        for h in history {
            let exec = CommandExecution(id: "mig-\(abs(h.command.hashValue))",
                                        startedAt: h.lastRunAt, exitCode: nil, duration: nil)
            byCommand[h.command] = CommandEntry(command: h.command, name: nil, cwd: h.cwd,
                                                favorite: false, executions: [exec])
        }
        for s in scripts {
            var entry = byCommand[s.command]
                ?? CommandEntry(command: s.command, name: s.name, cwd: s.cwd, favorite: false, executions: [])
            entry.favorite = true
            entry.name = s.name
            if entry.cwd == nil { entry.cwd = s.cwd }
            byCommand[s.command] = entry
        }
        return Array(byCommand.values)
    }
}
