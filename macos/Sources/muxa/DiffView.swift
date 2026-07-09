import SwiftUI

/// diff를 열 대상 — 변경 파일 또는 커밋. .sheet(item:)용 Identifiable.
enum GitDiffTarget: Identifiable {
    case file(GitFileChange)
    case commit(hash: String, subject: String)

    var id: String {
        switch self {
        case .file(let change): return "f:\(change.path)"
        case .commit(let hash, _): return "c:\(hash)"
        }
    }

    var title: String {
        switch self {
        case .file(let change): return change.path
        case .commit(_, let subject): return subject
        }
    }

    /// 탭 라벨(짧게).
    var tabTitle: String {
        switch self {
        case .file(let change): return basename(change.path)
        case .commit(let hash, _): return String(hash.prefix(7))
        }
    }

    var tabIcon: String {
        switch self {
        case .file: return "plusminus"
        case .commit: return "clock"
        }
    }
}

/// unified diff 뷰어(시트). +초록/-빨강/@@ 청록으로 라인 색을 준다. 읽기 전용.
/// 큰 diff 대비 LazyVStack + 가로·세로 스크롤. 폰트·색 고도화는 B(뷰어)에서.
struct DiffView: View {
    let target: GitDiffTarget
    let dir: String
    var onClose: () -> Void

    @State private var lines: [String] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            if !loaded {
                centerLabel("불러오는 중…")
            } else if lines.isEmpty {
                centerLabel("변경 내용 없음")
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(for: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(background(for: line))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plusminus").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            Text(target.title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            Button("닫기", action: onClose)
                .keyboardShortcut(.cancelAction) // Esc
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.pPanel)
    }

    private func centerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for line: String) -> Color {
        guard let first = line.first else { return Color.pFg }
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Color.pMuted }
        switch first {
        case "+": return .green
        case "-": return .red
        case "@": return .cyan
        case "d", "i", "n": return Color.pMuted // diff/index/new file 헤더 등
        default: return Color.pFg
        }
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .clear }
        switch line.first {
        case "+": return Color.green.opacity(0.10)
        case "-": return Color.red.opacity(0.10)
        default: return .clear
        }
    }

    private func load() async {
        loaded = false
        let text: String
        switch target {
        case .file(let change):
            text = await GitService.fileDiff(change, in: dir)
        case .commit(let hash, _):
            text = await GitService.commitDiff(hash, in: dir)
        }
        lines = text.components(separatedBy: "\n")
        loaded = true
    }
}
