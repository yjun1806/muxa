import SwiftUI

/// 활성 프로젝트 폴더의 git 상태 패널(우측). 브랜치·ahead/behind·변경 파일 목록.
/// 읽기 전용(M3). diff 뷰·스테이징은 후속(C-2 / M4).
struct GitPanel: View {
    let dir: String?

    @State private var status: GitStatus?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.pBorder).frame(height: 1)
            content
            Spacer(minLength: 0)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        .task(id: dir) { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Color.pMuted)
            Text("Git").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pFg)
            Spacer()
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pMuted)
            .help("새로고침")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    @ViewBuilder
    private var content: some View {
        if let status {
            branchRow(status)
            Rectangle().fill(Color.pBorder).frame(height: 1)
            if status.isClean {
                label("변경 없음")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(status.changes) { fileRow($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if dir == nil {
            label("프로젝트 경로 없음")
        } else {
            label(loaded ? "git 저장소 아님" : "불러오는 중…")
        }
    }

    private func branchRow(_ status: GitStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(Color.pMuted)
            Text(status.branch)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
            Spacer(minLength: 0)
            if status.ahead > 0 {
                counter("arrow.up", status.ahead)
            }
            if status.behind > 0 {
                counter("arrow.down", status.behind)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func counter(_ icon: String, _ n: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 9))
            Text("\(n)").font(.system(size: 11).monospacedDigit())
        }
        .foregroundStyle(Color.pMuted)
    }

    private func fileRow(_ change: GitFileChange) -> some View {
        HStack(spacing: 8) {
            Text(String(change.badge))
                .font(.system(size: 11, weight: .bold).monospaced())
                .foregroundStyle(badgeColor(change.badge))
                .frame(width: 12)
            Text(basename(change.path))
                .font(.system(size: 12))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
            Text(parentDir(change.path))
                .font(.system(size: 10))
                .foregroundStyle(Color.pMuted.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .help(change.path)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private func badgeColor(_ c: Character) -> Color {
        switch c {
        case "A", "?": return .green
        case "M": return .orange
        case "D": return .red
        case "R", "C": return .blue
        default: return Color.pMuted
        }
    }

    /// 경로의 상위 디렉토리(표시용, 없으면 빈 문자열).
    private func parentDir(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private func refresh() async {
        guard let dir else {
            status = nil
            loaded = true
            return
        }
        status = await GitService.status(in: dir)
        loaded = true
    }
}
