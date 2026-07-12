import Foundation

/// 익스플로러 트리 노드 — NSOutlineView가 참조 동일성을 요구해 class. 자식은 지연 로드·캐시.
final class FileNode: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    /// 지연 로드된 자식(nil=미로드). NSOutlineView가 펼칠 때 채운다.
    var children: [FileNode]?

    init(path: String, name: String, isDirectory: Bool) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
    }

    var id: String { path }
    static func == (l: FileNode, r: FileNode) -> Bool { l.path == r.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

/// 파일 트리 로딩 — 순수 함수(부작용 없음). CLAUDE.md: 트리 로직은 뷰가 아닌 함수로.
enum FileTree {
    /// 무시할 항목(대형 리포에서 트리·감시 폭주 방지 + OS 노이즈). dotfile을 보여도 이건 항상 숨긴다.
    static let ignored: Set<String> = [".git", "node_modules", ".build", ".worktrees", "target", "dist", ".next", ".DS_Store"]

    /// 디렉토리 자식 노드(디렉토리 우선·이름 자연 정렬). 실패 시 빈 배열.
    /// showHidden 기본 true — 개발 환경이라 `.env`·`.gitignore`·`.github` 등 dotfile은 보여준다.
    /// (진짜 노이즈는 위 `ignored`가 dotfile 여부와 무관하게 걸러낸다.)
    static func children(of dir: String, showHidden: Bool = true) -> [FileNode] {
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
