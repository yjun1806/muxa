import SwiftUI

/// 코드/텍스트 파일 뷰어 탭 — HighlighterSwift 신택스 하이라이트 + 줄번호(CodeTextView).
/// 바이너리·대형 파일은 가드. 읽기 전용.
struct CodeView: View {
    let target: FileViewTarget
    var chrome: Bool = true // 그룹 서브탭 안에서는 서브탭 바가 헤더 역할이라 자체 헤더를 숨긴다
    var onClose: () -> Void
    /// 본문 선택을 IDE 통합으로 흘려보낸다.
    var onSelection: (IdeSelection) -> Void = { _ in }

    @State private var html = ""
    @State private var state: LoadState = .loading
    @State private var watcher: FileWatcher? // 디스크 변경 시 자동 재로드
    @State private var lastMTime: Date?      // 이 파일 실제 변경만 재로드(FSEvents 재귀 소음 무시)

    enum LoadState { case loading, ok, tooLarge, binary, error }

    /// 통째 로드 상한(넘으면 tooLarge). 뷰어는 읽기용이라 보수적으로.
    private static let maxBytes = 2_000_000

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                ViewerHeader(icon: "doc.text", title: target.path, onClose: onClose)
                HDivider()
            }
            content
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

    @ViewBuilder private var content: some View {
        switch state {
        case .loading: centerLabel("불러오는 중…")
        case .tooLarge: centerLabel("파일이 너무 큽니다")
        case .binary: centerLabel("바이너리 파일")
        case .error: centerLabel("열 수 없음")
        case .ok: CodeWebView(html: html, filePath: target.path, onSelection: onSelection)
        }
    }

    private func centerLabel(_ t: String) -> some View {
        Text(t)
            .font(.muxa(.body))
            .foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        state = .loading
        let path = target.path
        let maxBytes = Self.maxBytes
        lastMTime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        // 파일 IO는 백그라운드에서(대형 파일이 메인 스레드를 막지 않게).
        let result: (LoadState, String) = await Task.detached {
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.intValue else { return (.error, "") }
            if size > maxBytes { return (.tooLarge, "") }
            guard let data = fm.contents(atPath: path) else { return (.error, "") }
            if data.prefix(8000).contains(0) { return (.binary, "") } // NUL 바이트 → 바이너리
            guard let text = String(data: data, encoding: .utf8) else { return (.binary, "") }
            return (.ok, text)
        }.value
        if result.0 == .ok {
            // Shiki(오프스크린 공유)로 토큰 색을 받아 정적 HTML로 만든다. 표시는 CodeWebView.
            let dark = GhosttyRuntime.systemIsDark
            let tokens = await ShikiHighlighter.shared.tokens(code: result.1, language: target.language, dark: dark)
            html = CodeHTML.code(tokens: tokens, dark: dark)
        }
        state = result.0
    }
}
