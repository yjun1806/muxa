import AppKit
import GhosttyKit

// muxa M0 PoC — 창 하나 + GhosttyKit 서피스 하나. 게이트: 한글 IME 실기기 검증.

guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
    fatalError("ghostty_init failed")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime?
    private var state: AppState?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime = GhosttyRuntime(), let app = runtime.app else {
            fatalError("GhosttyRuntime init failed")
        }
        self.runtime = runtime

        // 저장된 세션 복원(없으면 현재 디렉토리로 초기 워크스페이스 생성)
        let state = AppState()
        state.load()
        state.ensureInitial(path: SystemPaths.currentDir ?? SystemPaths.home)
        self.state = state

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "muxa"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.contentView = RootView(app: app, state: state, home: SystemPaths.home)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
