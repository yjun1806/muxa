import SwiftUI

/// 파일 익스플로러 패널(우측) — NSOutlineView 트리(FileExplorerOutline) 호스팅 + git 상태 로드.
/// git 상태는 FSEvents(FileWatcher)로 자동 갱신(색). GitPanel과 형제, 동일 골격.
/// 트리 구조 라이브 갱신은 새로고침/프로젝트 전환 시(후속: reloadItem 부분 갱신).
struct FileExplorerPanel: View {
    let root: String?
    /// 뷰어로 방금 연 파일 경로 — 트리에서 그 노드로 reveal(조상 폴더 펼침+선택+스크롤).
    var revealPath: String? = nil
    /// reveal 트리거 시퀀스(값이 바뀔 때만 reveal). 같은 경로 재-open도 반영.
    var revealSeq: Int = 0
    var onOpenFile: (String) -> Void
    var onOpenTerminal: (String) -> Void

    @State private var gitStatus = GitStatusMap()
    @State private var watcher: FileWatcher?
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            if let root {
                FileExplorerOutline(
                    root: root,
                    reloadToken: reloadToken,
                    gitStatus: gitStatus,
                    revealPath: revealPath,
                    revealSeq: revealSeq,
                    onOpenFile: onOpenFile,
                    onOpenTerminal: onOpenTerminal
                )
                .task(id: root) {
                    await loadGit(root)
                    watcher = FileWatcher(path: root)
                }
                .onChange(of: watcher?.changeSeq) { _, _ in
                    reloadToken += 1 // 트리 구조 라이브 갱신(펼침 상태는 보존됨)
                    Task { await loadGit(root) }
                }
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
                reloadToken += 1 // 트리 구조 새로 읽기
                if let root { Task { await loadGit(root) } }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted).help("새로고침")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(Color.pMuted)
            .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func loadGit(_ root: String) async {
        gitStatus = await GitService.statusMap(in: root)
    }
}
