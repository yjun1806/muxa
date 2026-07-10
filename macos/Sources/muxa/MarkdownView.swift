import SwiftUI

/// md/HTML 뷰어 탭 — 파일을 읽어 MarkdownWebView(markdown-it·highlight.js·mermaid)로 렌더.
/// 표·체크박스·코드 하이라이트·mermaid·이미지 지원. 읽기 전용. .html은 원문 그대로 렌더.
struct MarkdownView: View {
    let target: FileViewTarget
    var onClose: () -> Void

    @State private var content = ""
    @State private var state: LoadState = .loading

    enum LoadState { case loading, ok, tooLarge, error }

    /// md/html은 통째 로드. 문서라 코드보다 상한을 조금 크게.
    private static let maxBytes = 5_000_000

    private var isHTML: Bool { target.kind == .html }

    var body: some View {
        VStack(spacing: 0) {
            ViewerHeader(
                icon: isHTML ? "chevron.left.forwardslash.chevron.right" : "doc.richtext",
                title: target.path,
                onClose: onClose
            )
            Rectangle().fill(Color.pBorder).frame(height: 1)
            content(for: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) { await load() }
    }

    @ViewBuilder
    private func content(for state: LoadState) -> some View {
        switch state {
        case .loading: centerLabel("불러오는 중…")
        case .tooLarge: centerLabel("파일이 너무 큽니다")
        case .error: centerLabel("열 수 없음")
        case .ok: MarkdownWebView(content: content, isRawHTML: isHTML)
        }
    }

    private func centerLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12)).foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        state = .loading
        let path = target.path
        let maxBytes = Self.maxBytes
        let result: (LoadState, String) = await Task.detached {
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.intValue else { return (.error, "") }
            if size > maxBytes { return (.tooLarge, "") }
            guard let data = fm.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else { return (.error, "") }
            return (.ok, text)
        }.value
        state = result.0
        content = result.1
    }
}
