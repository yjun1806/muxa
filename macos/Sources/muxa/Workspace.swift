import Foundation

/// 프로젝트 = 한 폴더에서 시작하는 탭 묶음(독립 분할 레이아웃 = Bonsplit 1개).
/// 워크스페이스 하위. 경로는 워크스페이스 폴더를 상속하거나, 워크트리면 자체 경로를 가진다.
/// 분할·탭 상태는 Bonsplit(TerminalStore)이 소유하므로 여기엔 메타만 둔다.
struct Project: Codable, Identifiable {
    let id: String
    var name: String
    var path: String? // nil이면 워크스페이스 경로 상속. 워크트리면 자체 경로.
    /// 세션 기준선 커밋(rev-parse HEAD) — 첫 터미널 시작 시 1회 기록. "이번 세션에 에이전트가 한 일"의
    /// 기준점이다(base..HEAD). 옵셔널이라 하위호환(옛 저장분엔 없음). 리셋으로 현재 HEAD까지 "읽음" 처리.
    var sessionBaseHead: String?
    /// 장수 프로세스(dev 서버 등). 탭 트리 밖에 살고 실행은 tmux에 위임한다(Service.swift 참조).
    /// 여기 실려 Persisted에 자동 편승한다. 옵셔널이라 하위호환(옛 저장분엔 없음).
    var services: [Service]?
    /// 탭을 닫았지만 **안에서 작업이 돌고 있어 백그라운드로 남긴** tmux 세션들(L3).
    ///
    /// 여기 실려야 두 가지가 성립한다: ① 시작 시 GC가 고아로 오인해 죽이지 않는다(그러면 남긴 의미가
    /// 없다) ② 사용자가 목록에서 되찾을 수 있다. 기록 없이 남기면 **눈에 안 보이는 유령**이 된다.
    var detached: [DetachedSession]?
}

/// 탭이 닫혔지만 살아남은 tmux 세션 — 되찾을 수 있는 백그라운드 작업.
struct DetachedSession: Codable, Identifiable, Equatable {
    /// tmux 세션명이 곧 신원이다(중복 불가).
    var id: String { session }
    let session: String
    /// 남길 때 그 안에서 돌고 있던 명령(표시용) — "무엇을 되찾는 건지" 사용자가 알아야 한다.
    var command: String
    var cwd: String?
    /// 닫을 때의 탭 이름. **"claude"만으로는 어느 세션인지 모른다** — 같은 명령을 여러 탭에서
    /// 돌렸다면 구별할 방법이 없다. 사용자가 손으로 붙인 이름이면 그게 가장 강한 단서다.
    var title: String?
    /// 언제 닫았는지 — 목록이 여럿일 때 "방금 그거"를 짚는 기준. 옵셔널(구 기록엔 없음).
    var detachedAt: Date?
}

/// 워크스페이스 = 메인 폴더(레포) + 프로젝트 묶음. 사이드바 최상위.
/// (src/workspace.ts 이식, 프로젝트 계층 추가)
struct Workspace: Codable, Identifiable {
    let id: String
    var path: String? // 메인 시작 폴더. 초기 워크스페이스는 프로세스 cwd라 nil일 수 있다
    var name: String // 표시 이름(경로 basename)
    var projects: [Project]
    var activeProjectId: String
    /// 사용자가 이미 처리(추가/무시)한 외부 워크트리 경로 — 인박스 "추가?" 제안의 baseline(D31).
    /// 영속이라 재시작해도 다시 조르지 않는다. 옵셔널이라 하위호환(옛 저장분엔 없음 → nil로 디코드).
    var acknowledgedWorktreePaths: [String]? = nil

    var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }
}

func newId() -> String {
    UUID().uuidString
}

func basename(_ path: String) -> String {
    let trimmed = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    let parts = trimmed.split(separator: "/")
    return parts.last.map(String.init) ?? path
}

/// 경로 비교 안정화 — 뒤 슬래시를 뗀다(`/a/b/` == `/a/b`). 루트 `/`는 보존한다.
/// (심링크는 풀지 않는다 — 순수 함수라 파일시스템을 안 건드린다. 필요하면 호출부에서 미리 resolve)
func normalizePath(_ path: String) -> String {
    var result = path
    while result.count > 1, result.hasSuffix("/") { result.removeLast() }
    return result
}

/// 표시용 경로 — 홈 접두를 ~로 축약.
func displayPath(_ path: String?, home: String?) -> String {
    guard let path else { return "" }
    if let home, path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
    return path
}

/// 기본 프로젝트 1개(= 메인 폴더)를 가진 워크스페이스를 만든다.
func createWorkspace(path: String? = nil, name: String? = nil) -> Workspace {
    let wsName = name ?? (path.map(basename) ?? "workspace")
    let mainProject = Project(id: newId(), name: "메인", path: nil) // nil = 워크스페이스 경로 상속
    return Workspace(
        id: newId(),
        path: path,
        name: wsName,
        projects: [mainProject],
        activeProjectId: mainProject.id
    )
}

/// 새 프로젝트(워크트리 등) — 자체 경로 지정 가능(nil이면 워크스페이스 경로 상속).
func createProject(name: String, path: String? = nil) -> Project {
    Project(id: newId(), name: name, path: path)
}
