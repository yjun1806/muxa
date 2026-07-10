import SwiftUI

/// Markdown 뷰어 탭 — 네이티브 렌더(블록: heading/list/codefence/quote/문단, 인라인: AttributedString).
/// 표·mermaid 등 고급은 후속(WKWebView 경로로 이 뷰만 교체). 읽기 전용.
struct MarkdownView: View {
    let target: FileViewTarget
    var onClose: () -> Void

    @State private var blocks: [MarkdownBlock] = []
    @State private var state: LoadState = .loading

    enum LoadState { case loading, ok, tooLarge, error }

    /// 통째 로드 상한(넘으면 tooLarge). CodeView와 같은 보수적 상한.
    private static let maxBytes = 2_000_000

    var body: some View {
        VStack(spacing: 0) {
            ViewerHeader(icon: "doc.richtext", title: target.path, onClose: onClose)
            Rectangle().fill(Color.pBorder).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading: centerLabel("불러오는 중…")
        case .tooLarge: centerLabel("파일이 너무 큽니다")
        case .error: centerLabel("열 수 없음")
        case .ok:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func centerLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12)).foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(Color.pFg)
                .padding(.top, level <= 2 ? 8 : 2)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 14))
                .foregroundStyle(Color.pFg)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, _):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(Color.pMuted)
                Text(inline(text))
                    .font(.system(size: 14)).foregroundStyle(Color.pFg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)
        case .code(let code):
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Color.pFg)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pPanel)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(Color.pBorder).frame(width: 3)
                Text(inline(text))
                    .font(.system(size: 14)).foregroundStyle(Color.pMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .rule:
            Rectangle().fill(Color.pBorder).frame(height: 1).padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 17
        default: return 15
        }
    }

    /// 인라인 강조(**bold**·*italic*·`code`·[link]())를 AttributedString으로. 실패 시 평문.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private func load() async {
        state = .loading
        let path = target.path
        let maxBytes = Self.maxBytes
        let result: (LoadState, [MarkdownBlock]) = await Task.detached {
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.intValue else { return (.error, []) }
            if size > maxBytes { return (.tooLarge, []) }
            guard let data = fm.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else { return (.error, []) }
            return (.ok, Markdown.parse(text))
        }.value
        state = result.0
        blocks = result.1
    }
}
