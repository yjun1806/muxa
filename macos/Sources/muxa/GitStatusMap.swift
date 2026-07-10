import AppKit

/// 파일 하나의 git 상태(익스플로러 파일명 색·배지용).
enum GitFileStatus {
    case modified, added, deleted, renamed, untracked, conflict

    var color: NSColor {
        switch self {
        case .modified: return Palette.gitModified
        case .added, .untracked: return Palette.gitAdded
        case .deleted: return Palette.gitDeleted
        case .renamed: return Palette.gitRenamed
        case .conflict: return Palette.gitConflict
        }
    }

    var badge: Character {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "U"
        case .conflict: return "C"
        }
    }
}

/// 경로 → git 상태 맵. 파일 상태 + 조상 폴더로 전파(닫힌 폴더도 색). 값 타입.
struct GitStatusMap {
    private let byPath: [String: GitFileStatus]

    init(byPath: [String: GitFileStatus] = [:]) { self.byPath = byPath }

    func status(for path: String) -> GitFileStatus? { byPath[path] }
    var isEmpty: Bool { byPath.isEmpty }
}
