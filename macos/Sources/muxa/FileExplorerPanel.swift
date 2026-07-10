import SwiftUI

/// 파일 익스플로러 패널(우측) — 루트 폴더의 트리. 파일 클릭 → 뷰어 탭으로 연다(onOpenFile).
/// GitPanel과 형제, 동일 골격(width 280, header + 본문). 읽기 전용.
///
/// 디렉토리 자식은 펼칠 때 1회만 백그라운드로 읽어 `cache`에 담는다 — body에서 디스크 IO를 하지 않아
/// 리렌더·토글마다 메인 스레드가 막히지 않는다. 새로고침은 캐시를 비우고 루트만 다시 읽는다.
struct FileExplorerPanel: View {
    let root: String?
    var onOpenFile: (String) -> Void

    @State private var expanded: Set<String> = []
    @State private var cache: [String: [FileNode]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            if let root {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ExplorerRows(dir: root, depth: 0, expanded: expanded, cache: cache,
                                     onToggle: toggle, onOpenFile: onOpenFile)
                    }
                    .padding(.vertical, 4)
                }
                .task(id: root) { await load(root) }
            } else {
                label("프로젝트 경로 없음")
            }
            Spacer(minLength: 0)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            Text(root.map(basename) ?? "익스플로러")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pFg).lineLimit(1)
            Spacer(minLength: 4)
            Button {
                expanded = []
                cache = [:]
                if let root { Task { await load(root) } }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted).help("접기·새로고침")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    /// 폴더 펼침/접힘 — 처음 펼칠 때 자식을 백그라운드로 로드해 캐시에 담는다.
    private func toggle(_ path: String) {
        var next = expanded // 불변 업데이트(coding-style)
        if next.contains(path) {
            next.remove(path)
        } else {
            next.insert(path)
            if cache[path] == nil { Task { await load(path) } }
        }
        expanded = next
    }

    /// 디렉토리 자식을 백그라운드에서 읽어 캐시에 저장(메인 스레드 디스크 IO 회피).
    private func load(_ dir: String) async {
        let nodes = await Task.detached { FileTree.children(of: dir) }.value
        cache[dir] = nodes
    }
}

/// 재귀 트리 행 묶음 — SwiftUI에서 재귀 뷰는 별도 View struct여야 한다(opaque 자기참조 회피).
/// cache/expanded를 값으로 받아 body는 캐시만 읽는다(디스크 IO 없음). 토글·열기는 콜백으로 상위에 위임.
private struct ExplorerRows: View {
    let dir: String
    let depth: Int
    let expanded: Set<String>
    let cache: [String: [FileNode]]
    var onToggle: (String) -> Void
    var onOpenFile: (String) -> Void

    var body: some View {
        ForEach(cache[dir] ?? [], id: \.id) { node in
            row(node)
            if node.isDirectory, expanded.contains(node.path) {
                ExplorerRows(dir: node.path, depth: depth + 1, expanded: expanded, cache: cache,
                             onToggle: onToggle, onOpenFile: onOpenFile)
            }
        }
    }

    private func row(_ node: FileNode) -> some View {
        Button {
            if node.isDirectory { onToggle(node.path) } else { onOpenFile(node.path) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory
                    ? (expanded.contains(node.path) ? "chevron.down" : "chevron.right")
                    : "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: 12)
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12 + 10)
            .padding(.trailing, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(node.path)
    }
}
