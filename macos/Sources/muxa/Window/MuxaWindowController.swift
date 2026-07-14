import AppKit

/// 창 하나의 **경계** — NSWindow 생성·설정·델리게이트를 한곳에 모은다.
///
/// 메인 창과 분리 창은 같은 크롬(타이틀바 투명 + 신호등 중앙 정렬)을 쓰고, 다른 것은 두 가지뿐이다:
/// 프레임 출처(메인 = UserDefaults autosave, 분리 창 = 저장된 FrameSnapshot + cascade)와
/// 닫기 의미(메인 = 앱 종료, 분리 창 = 무손실 재합치기 — D30).
@MainActor
final class MuxaWindowController: NSObject, NSWindowDelegate {
    /// 이 창의 신원. 키 라우팅(`WindowHost.id(for:)`)과 소유권 스탬프가 같은 값을 쓴다.
    let id: WindowID
    let window: NSWindow

    /// 닫아도 되는가. 메인 창의 종료 시트가 여기 꽂힌다 — nil이면 그냥 닫는다(분리 창).
    var shouldClose: (() -> Bool)?
    /// 창이 실제로 닫히는 순간. 분리 창의 재합치기·레지스트리 정리가 여기 꽂힌다.
    var willClose: (() -> Void)?
    /// 창이 움직이거나 크기가 바뀌었다 — 분리 창의 프레임 영속이 여기 꽂힌다(메인은 UserDefaults autosave).
    var onFrameChange: ((FrameSnapshot) -> Void)?

    /// 메인 창 프레임 저장 키(AppKit이 UserDefaults에 크기·위치를 보관한다).
    /// 개발 빌드와 릴리스가 같은 키를 쓰면 창 위치가 서로 튀므로 앱 이름으로 갈라둔다.
    static let mainFrameAutosaveName = "\(AppInfo.name).main"

    /// 기본 크기 — 저장분이 없거나 화면 밖일 때.
    private static let defaultSize = NSSize(width: 1000, height: 680)

    init(id: WindowID, content: NSView, frame: NSRect? = nil) {
        self.id = id
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        // **우리가 창을 붙잡고 있으므로 창이 스스로를 놓게 두면 안 된다.**
        // 코드로 만든 NSWindow는 isReleasedWhenClosed가 기본 true다 — close()가 자기 자신을 release한다.
        // 강참조(`let window`)를 쥔 채로 그걸 허용하면 과다 해제로 즉사한다. 메인 창은 "닫기 = 앱 종료"라
        // 이 버그가 드러날 자리가 없었지만, 분리 창은 **닫혀도 앱이 산다** — 재합치기에서 바로 터졌다.
        window.isReleasedWhenClosed = false
        window.title = AppInfo.name
        // 시스템 환경설정의 "항상 탭으로 열기"가 켜져 있으면 새 창이 기존 창의 **탭**으로 병합된다 —
        // 그러면 창 분리가 통째로 무력화된다(분리했는데 같은 창 안이다). 탭 병합을 아예 끈다.
        window.tabbingMode = .disallowed
        // 콘텐츠를 타이틀바까지 끌어올리고(fullSizeContentView) 신호등만 남긴다. 상단바 컨트롤은
        // SwiftUI 본문 최상단에 직접 둔다 — 타이틀바 액세서리는 렌더가 불안정해 비어 보였다.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true // 빈 영역 드래그로 창 이동(Tauri drag-region 대체)
        window.backgroundColor = Palette.panel // 창 배경을 상단바와 같은 회색으로
        window.contentView = content
        window.delegate = self

        restoreFrame(frame)
    }

    /// 창을 띄우고 신호등을 상단바 중앙으로 내린다.
    func show() {
        window.makeKeyAndOrderFront(nil)
        TrafficLights.align(in: window, barHeight: RowHeight.topBar)
    }

    /// 창 크기·위치 복원.
    ///
    /// **화면 밖 검사는 우리가 한다.** setFrameUsingName이 알아서 보정해 줄 거라 믿었다가 창이 통째로
    /// 화면 밖(외장 모니터를 뽑은 뒤의 옛 좌표)에 떠서 앱이 보이지 않는 회귀를 냈다. 모니터를 뽑거나
    /// 해상도가 바뀌면 저장된 좌표는 언제든 무효가 되므로, 복원 직후 실제로 보이는지 직접 확인한다.
    /// (분리 창은 같은 판정을 `WindowFrame.restore`가 미리 끝낸 뒤 프레임을 건네준다.)
    private func restoreFrame(_ frame: NSRect?) {
        if let frame {
            window.setFrame(frame, display: false)
            return
        }
        guard id.isMain else {
            // 저장분이 없는 분리 창 — 기본 크기로 계단식 배치(기존 창을 정확히 덮지 않게).
            window.setContentSize(Self.defaultSize)
            window.center()
            window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            return
        }
        window.setFrameAutosaveName(Self.mainFrameAutosaveName)
        let restored = window.setFrameUsingName(Self.mainFrameAutosaveName)
        if !restored || !WindowFrame.isReachable(window.frame, screens: NSScreen.screens.map(\.visibleFrame)) {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool { shouldClose?() ?? true }

    func windowWillClose(_ notification: Notification) { willClose?() }

    // 시스템은 리사이즈·활성화·풀스크린 전환 때 타이틀바를 다시 레이아웃하며 신호등을 표준 위치로
    // 되돌린다. 그때마다 상단바 중앙으로 다시 내린다.
    func windowDidResize(_ notification: Notification) { realignTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { realignTrafficLights() }

    // 프레임 보고는 **드래그·리사이즈가 끝난 뒤**의 좌표까지 반드시 포함해야 한다 —
    // 저장 쪽(AppState.recordFrame)이 trailing 디바운스라 마지막 한 번이 곧 저장되는 값이다.
    func windowDidMove(_ notification: Notification) { reportFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { reportFrame() }

    /// 지금 프레임을 알린다 — 창을 처음 띄운 직후에도 한 번(cascade로 정해진 위치를 모델이 알아야
    /// 재시작 때 같은 자리에 뜬다).
    func reportFrame() { onFrameChange?(FrameSnapshot(window.frame)) }

    /// 창별 포커스 계약 — 키를 얻고 잃을 때 **그 창의** 터미널 서피스 포커스만 켜고 끈다.
    /// 안 끄면 창이 둘일 때 양쪽 서피스가 동시에 focused=true로 남아 커서가 두 개로 깜빡인다.
    func windowDidBecomeKey(_ notification: Notification) {
        focusedTerm?.setSurfaceFocus(true)
        realignTrafficLights()
    }

    func windowDidResignKey(_ notification: Notification) {
        focusedTerm?.setSurfaceFocus(false)
    }

    private var focusedTerm: TermView? { window.firstResponder as? TermView }

    private func realignTrafficLights() {
        TrafficLights.align(in: window, barHeight: RowHeight.topBar)
    }
}
