import AppKit
import SwiftUI

/// 세션 관리자 창 — 워크스페이스 창과 독립적으로 뜨는 유틸리티 창(YJ-6).
///
/// `MuxaWindowController`(투명 타이틀바 + 신호등 중앙 정렬 + 터미널 포커스 계약)를 쓰지 않는다.
/// 그 크롬은 터미널을 담는 창의 것이고, 여기는 **표준 macOS 유틸리티 창**이 맞다 — 활성 상태 보기처럼
/// 제목이 보이고, 옆에 띄워두고 작업하는 창이다.
///
/// `AppState`에 얹지 않는다: AppState는 이미 2900줄대의 god object이고(docs/SERVICE-REVIEW.md)
/// 이 창은 워크스페이스·탭·영속과 아무것도 공유하지 않는다.
@MainActor
final class SessionManagerWindow: NSObject, NSWindowDelegate {
    static let shared = SessionManagerWindow()

    private let monitor = SessionMonitor()
    private var window: NSWindow?

    /// 창이 앱에게 요청하는 것들 — **창은 `AppState`를 모른다**(일부러). 여는 쪽이 꽂아 준다.
    struct Routing {
        /// 그 세션의 탭을 앞으로.
        let reveal: (String) -> Void
        /// 그 세션의 탭을 **완전히 닫는다**(세션 kill + 탭 닫기). 이 앱의 탭이 아니면 false —
        /// 그때는 호출부가 tmux 세션만 직접 죽인다.
        let closeTab: (String) -> Bool
    }

    private var routing: Routing?

    /// 세션 관리자를 연다 — **`AppState`를 아는 유일한 자리.**
    /// 창 자체는 워크스페이스도 탭도 모른다(일부러). 진입점이 둘(레일 버튼·창 메뉴)이라
    /// 배선을 여기 모으지 않으면 같은 세 줄이 두 곳에서 갈린다.
    static func open(for state: AppState) {
        shared.show(knownProjectIds: collectKnownProjectIds(in: state.workspaces),
                    routing: Routing(reveal: { state.revealSession(named: $0) },
                                     closeTab: { state.closeSession(named: $0) }))
    }

    /// 창을 띄우고 폴링을 시작한다. 이미 떠 있으면 앞으로 가져온다.
    /// - Parameter knownProjectIds: 고아 표시의 입력(`AppState`가 아는 프로젝트 전부).
    func show(knownProjectIds: Set<String>, routing: Routing) {
        monitor.knownProjectIds = knownProjectIds
        self.routing = routing
        let window = window ?? makeWindow()
        self.window = window
        monitor.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            // 열 아홉 개가 잘리지 않을 만큼. 활성 상태 보기의 기본 창과 비슷한 비율이다.
            contentRect: NSRect(origin: .zero, size: NSSize(width: 1120, height: 620)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "세션 관리자"
        // 코드로 만든 NSWindow는 닫힐 때 자기를 release한다 — 우리가 강참조를 쥐고 있으므로
        // 그대로 두면 두 번째로 열 때 과다 해제로 즉사한다(`MuxaWindowController`가 같은 이유로 끈다).
        window.isReleasedWhenClosed = false
        // "항상 탭으로 열기"가 켜져 있으면 워크스페이스 창의 탭으로 병합돼 유틸리티 창이 아니게 된다.
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("\(AppInfo.name).sessionManager")
        window.contentView = NSHostingView(rootView: SessionManagerView(
            monitor: monitor,
            onReveal: { [weak self] name in self?.routing?.reveal(name) },
            onCloseTab: { [weak self] name in self?.routing?.closeTab(name) ?? false }
        ))
        window.delegate = self
        if window.frame.origin == .zero { window.center() }
        return window
    }

    /// 창이 닫히면 폴링을 멈춘다 — 아무도 안 보는 화면을 위해 2초마다 커널과 tmux를 묻지 않는다.
    /// 창 객체는 남겨 다음에 같은 자리·같은 크기로 다시 뜬다.
    func windowWillClose(_ notification: Notification) {
        monitor.stop()
    }
}
