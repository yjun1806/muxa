import Foundation

/// 익스플로러용 git 상태 맵 — 트리 파일명 색·폴더 전파 배지.
extension GitService {
    /// 경로→상태 맵. `git status --porcelain=v1 -z`로 얻고, 각 변경을 조상 폴더로 전파한다.
    static func statusMap(in dir: String) async -> GitStatusMap {
        guard let root = await repoRoot(in: dir) else { return GitStatusMap() }
        let r = await run(["-c", "core.quotepath=false", "status", "--porcelain=v1", "-z"], in: root)
        guard r.exitCode == 0 else { return GitStatusMap() }
        return parseStatusMap(r.stdout, root: root)
    }

    static func parseStatusMap(_ output: String, root: String) -> GitStatusMap {
        var map: [String: GitFileStatus] = [:]
        // -z: 각 레코드가 NUL로 구분. rename/copy는 다음 레코드가 원본 경로라 한 칸 더 소비한다.
        let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < records.count {
            let rec = records[i]
            guard rec.count >= 4 else { i += 1; continue }
            let x = rec[rec.startIndex]
            let y = rec[rec.index(rec.startIndex, offsetBy: 1)]
            let path = String(rec.dropFirst(3))
            let status = classify(x: x, y: y)
            if x == "R" || x == "C" { i += 1 } // 원본 경로 레코드 스킵
            let abs = (root as NSString).appendingPathComponent(path)
            map[abs] = status
            propagate(abs, root: root, status: status, into: &map)
            i += 1
        }
        return GitStatusMap(byPath: map)
    }

    private static func classify(x: Character, y: Character) -> GitFileStatus {
        if x == "?" { return .untracked }
        if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") { return .conflict }
        let s = x != " " ? x : y
        switch s {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R", "C": return .renamed
        default: return .modified
        }
    }

    /// 변경 파일의 조상 폴더에 상태를 전파한다(이미 있으면 유지 — 첫 하위 변경색).
    private static func propagate(_ path: String, root: String, status: GitFileStatus, into map: inout [String: GitFileStatus]) {
        var dir = (path as NSString).deletingLastPathComponent
        while dir.hasPrefix(root), dir != root, dir != "/" {
            if map[dir] == nil { map[dir] = status }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }
}
