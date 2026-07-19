import AppKit

/// 파일 하나의 git 상태(익스플로러 파일명 색).
///
/// **색·라벨은 여기서 정하지 않는다** — `GitStatusStyle`(git 축 SSOT)이 porcelain 문자를 기준으로
/// 소유하고, 이 열거형은 `GitStatusStyle.code(_:)`로 문자에 환원돼 같은 테이블을 거친다.
/// (예전엔 여기 `badge` 프로퍼티가 untracked를 `U`, conflict를 `C`로 내보냈다 — git 원문에서
/// `U`=unmerged, `C`=copied라 의미가 정반대였다. 소비처가 없어 화면엔 안 나왔지만 지뢰라 지웠다.)
enum GitFileStatus {
    case modified, added, deleted, renamed, untracked, conflict

    /// 익스플로러 파일명 색 — `GitStatusStyle`에 위임(매핑을 두 곳에 두지 않는다).
    var color: NSColor { NSColor(GitStatusStyle.color(self)) }
}

/// 경로 → git 상태 맵. 파일 상태 + 조상 폴더로 전파(닫힌 폴더도 색). 값 타입.
struct GitStatusMap {
    private let byPath: [String: GitFileStatus]

    init(byPath: [String: GitFileStatus] = [:]) { self.byPath = byPath }

    func status(for path: String) -> GitFileStatus? { byPath[path] }
    var isEmpty: Bool { byPath.isEmpty }
}
