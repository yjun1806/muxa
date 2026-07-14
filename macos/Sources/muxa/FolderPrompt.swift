import AppKit

/// 폴더 하나를 고르는 표준 패널 — 새 워크스페이스·새 프로젝트·기본 경로 변경이 공유한다
/// (같은 NSOpenPanel 설정이 세 곳에 흩어져 있었다 → 추출). 취소·닫기는 nil.
@MainActor
enum FolderPrompt {
    static func pick(startingAt path: String? = nil,
                     prompt: String? = nil, message: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let prompt { panel.prompt = prompt }
        if let message { panel.message = message }
        panel.directoryURL = URL(fileURLWithPath: path ?? SystemPaths.home)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
