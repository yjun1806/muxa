import SwiftUI

/// md/HTML 뷰어 탭 — 파일을 읽어 MarkdownWebView(markdown-it·highlight.js·mermaid)로 렌더.
/// 표·체크박스·코드 하이라이트·mermaid·이미지 지원. 읽기 전용. .html은 원문 그대로 렌더.
struct MarkdownView: View {
    let target: FileViewTarget
    var chrome: Bool = true // 그룹 서브탭 안에서는 자체 헤더 숨김(서브탭 바가 헤더 역할)
    var onClose: () -> Void
    /// 문서 내 로컬 파일 링크를 앱 내 새 탭으로 연다.
    var onOpenFile: (String) -> Void = { _ in }
    /// 문서 내 외부 http(s) 링크를 인앱 브라우저 새 탭으로 연다.
    var onOpenURL: (URL) -> Void = { _ in }

    @State private var content = ""
    @State private var state: LoadState = .loading
    @State private var watcher: FileWatcher? // 디스크 변경 시 자동 재로드
    @State private var lastMTime: Date?      // 이 파일 실제 변경만 재로드(FSEvents 재귀 소음 무시)

    enum LoadState { case loading, ok, tooLarge, error }

    /// md/html은 통째 로드. 문서라 코드보다 상한을 조금 크게.
    private static let maxBytes = 5_000_000

    private var isHTML: Bool { target.kind == .html }

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                ViewerHeader(
                    icon: isHTML ? "chevron.left.forwardslash.chevron.right" : "doc.richtext",
                    title: target.path,
                    onClose: onClose
                )
                HDivider()
            }
            content(for: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) {
            await load()
            watcher = FileWatcher(path: (target.path as NSString).deletingLastPathComponent)
        }
        .onChange(of: watcher?.changeSeq) { _, _ in Task { await reloadIfChanged() } }
    }

    /// FSEvents는 부모 디렉토리 전체(재귀)를 알린다 → 이 파일 mtime이 실제 바뀐 경우만 재로드.
    private func reloadIfChanged() async {
        let m = (try? FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate]) as? Date
        guard m != lastMTime else { return }
        await load()
    }

    @ViewBuilder
    private func content(for state: LoadState) -> some View {
        switch state {
        case .loading: centerLabel("불러오는 중…")
        case .tooLarge: centerLabel("파일이 너무 큽니다")
        case .error: centerLabel("열 수 없음")
        case .ok: MarkdownWebView(
            content: content, isRawHTML: isHTML,
            baseDir: (target.path as NSString).deletingLastPathComponent,
            onOpenFile: onOpenFile,
            onOpenURL: onOpenURL
        )
        }
    }

    private func centerLabel(_ t: String) -> some View {
        Text(t)
            .font(.muxa(.body)).foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        state = .loading
        let path = target.path
        lastMTime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
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
