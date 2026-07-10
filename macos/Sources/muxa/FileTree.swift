import Foundation

/// 익스플로러 트리 노드(값 타입). 부작용 없는 순수 데이터. (cmux FileExplorerEntry 대응)
struct FileNode: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool

    var id: String { path }
}

/// 파일 트리 로딩 — 순수 함수(부작용 없음). CLAUDE.md: 트리 조작 같은 순수 로직은 뷰가 아닌 함수로.
enum FileTree {
    /// 무시할 디렉토리(대형 리포에서 트리·감시 폭주 방지).
    static let ignored: Set<String> = [".git", "node_modules", ".build", ".worktrees", "target", "dist", ".next"]

    /// 디렉토리의 직속 자식을 로드한다(디렉토리 우선, 이름 자연 정렬). 실패(권한 등) 시 빈 배열.
    /// 숨김 파일은 showHidden일 때만, 무시 디렉토리는 항상 제외.
    static func children(of dir: String, showHidden: Bool = false) -> [FileNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let nodes = entries.compactMap { name -> FileNode? in
            if ignored.contains(name) { return nil }
            if !showHidden && name.hasPrefix(".") { return nil }
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { return nil }
            return FileNode(path: full, name: name, isDirectory: isDir.boolValue)
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory } // 디렉토리 먼저
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
