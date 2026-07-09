import AppKit
import GhosttyKit
import SwiftUI

// muxa — SwiftUI 크롬 + AppKit(GhosttyKit) 터미널 하이브리드 (DESIGN.md D16).
// AppKit이 NSWindow·activation을 제어(raw 실행에도 창이 확실히 뜬다)하고,
// NSHostingView로 SwiftUI UI를 그 안에 임베드한다. Ghostty와 같은 구조.

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "muxa"
        window.center()
        window.contentView = NSHostingView(
            rootView: ContentView(app: app, state: state, home: SystemPaths.home)
        )
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
