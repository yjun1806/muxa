import AppKit

/// 모델(`[ProjectWindow]`) ⇄ 실물(`NSWindow`)의 **유일한 경계**.
///
/// - 레지스트리: `NSWindow` → `WindowID`. **모르는 창은 nil**을 돌려준다(FloatingPanel·시트·팝오버) —
///   키 라우팅이 지금처럼 그대로 통과해야 한다(회귀 0).
/// - reconcile: `sync(_:)` 하나가 모델에 있는데 없는 창을 열고, 없는데 있는 창을 닫는다(I4).
///   `projectWindows`를 바꾸는 모든 경로가 여기를 통과하므로 유령 창·도달 불가 프로젝트가 생길 수 없다.
@MainActor
final class WindowHost {
    /// 분리 창 본문을 만드는 팩토리. **P5에서 `ProjectWindowView`를 꽂는다** —
    /// 그전에는 분리 창을 만드는 진입점이 없어(모델이 늘 비어 있다) 이 경로가 실행되지 않는다.
    var makeProjectContent: ((WindowID) -> NSView)?

    /// 분리 창이 닫혔다 — 무손실 재합치기(D30)의 착지점. `AppState.rejoin`이 꽂힌다.
    var onProjectWindowClosed: ((WindowID) -> Void)?

    /// 분리 창이 움직였다/크기가 바뀌었다 — `AppState.recordFrame`(메모리 즉시 + 저장 디바운스)이 꽂힌다.
    var onFrameChange: ((WindowID, FrameSnapshot) -> Void)?

    /// 스크래치(~) 독립 창 — **`controllers`/`sync` 밖**에 따로 둔다(reconcile이 절대 못 닫게, 이게 pivot의 요지).
    /// `projectWindows`에 스크래치가 없으므로 sync는 이 창을 모른다. 키 라우팅·배지 게이트만 아래 accessor로 합류한다.
    private var scratchController: MuxaWindowController?
    var makeScratchContent: (() -> NSView)?
    /// 스크래치 창이 닫혔다 = **종료(파괴)**. rejoin 아님 — `AppState.scratchClosed`가 store를 버린다.
    var onScratchClosed: (() -> Void)?

    /// `NSWindow.delegate`는 weak라 컨트롤러를 여기서 붙잡는다. 창이 닫히면(`willClose`) 즉시 지운다.
    private var controllers: [WindowID: MuxaWindowController] = [:]

    /// 메인 창처럼 밖에서 만들어진 창을 레지스트리에 넣는다.
    func register(_ controller: MuxaWindowController) {
        controllers[controller.id] = controller
    }

    /// 이 NSWindow가 우리가 아는 창인가 — 아니면 nil(키 라우팅은 그대로 통과시킨다).
    func id(for window: NSWindow) -> WindowID? {
        if let c = scratchController, c.window === window { return Scratch.windowId }
        return controllers.first { $0.value.window === window }?.key
    }

    func window(_ id: WindowID) -> NSWindow? {
        if id == Scratch.windowId { return scratchController?.window }
        return controllers[id]?.window
    }

    /// 그 창을 앞으로. 창이 없으면 false — 호출자가 self-heal(메인으로 재합치기)한다.
    ///
    /// **최소화 복원을 먼저 한다.** `makeKeyAndOrderFront`는 Dock에 접힌 창을 되살리지 못하는데,
    /// 그래도 true를 돌려주면 호출자(알림 클릭·사이드바 클릭)는 성공으로 믿는다 —
    /// 사용자 눈엔 "알림을 눌렀는데 아무 창도 안 뜬다"가 된다.
    @discardableResult
    func raise(_ id: WindowID) -> Bool {
        let target = id == Scratch.windowId ? scratchController?.window : controllers[id]?.window
        guard let window = target else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// 지금 **실제로 눈에 들어와 있는** 창들 — 배지 게이트(`visibleActiveProjectIds`)의 입력.
    /// 알림 게이트(`TerminalStore.isTabVisible`)와 **같은 순수 판정**을 쓴다 — 두 게이트의 "보인다"가
    /// 어긋나면 최소화된 창의 프로젝트에 알림은 뜨는데 배지는 안 붙는다(놓치면 되찾을 단서가 없다).
    var visibleWindowIds: Set<WindowID> {
        let appActive = NSApp.isActive
        // 스크래치 창도 같은 판정으로 합류시킨다 — 포커스된 스크래치 세션에 배지가 헛붙지 않게(§1).
        var all = Array(controllers)
        if let c = scratchController { all.append((Scratch.windowId, c)) }
        return Set(all.compactMap { id, controller -> WindowID? in
            let window = controller.window
            return WindowVisibility.isVisible(appActive: appActive,
                                              windowVisible: window.isVisible,
                                              miniaturized: window.isMiniaturized,
                                              occluded: !window.occlusionState.contains(.visible)) ? id : nil
        })
    }

    /// 창 제목 — `titleVisibility = .hidden`이라 크롬엔 안 보이지만 **'창' 메뉴에는 그대로 나온다**.
    /// 모든 창이 "muxa"면 창을 잃었을 때 되찾을 유일한 UI가 동명 항목만 나열한다.
    func setTitle(_ id: WindowID, _ title: String) {
        guard let window = controllers[id]?.window, window.title != title else { return }
        window.title = title
    }

    /// 모델 ⇄ 실물 reconcile(I4). 메인 창은 모델 밖(여집합 — D29)이라 건드리지 않는다.
    func sync(_ windows: [ProjectWindow]) {
        let wanted = Set(windows.map(\.id))
        // 순회 대상을 먼저 확정한다 — close()는 willClose를 **동기로** 부르고, 그 콜백(재합치기)이
        // 다시 sync를 타고 들어와 controllers를 바꾼다. 살아 있는 컬렉션을 돌면서 닫으면 안 된다.
        let doomed = controllers.keys.filter { !$0.isMain && !wanted.contains($0) }
        for id in doomed {
            controllers[id]?.window.close() // willClose → 레지스트리에서 스스로 빠진다
        }
        for model in windows where controllers[model.id] == nil {
            open(model)
        }
    }

    private func open(_ model: ProjectWindow) {
        guard let content = makeProjectContent?(model.id) else { return }
        let frame = WindowFrame.restore(model.frame, screens: NSScreen.screens.map(\.visibleFrame))
        let controller = MuxaWindowController(id: model.id, content: content, frame: frame)
        let id = model.id
        // 닫히는 즉시 레지스트리에서 뺀 **뒤** 재합치기를 알린다 — 그래야 rejoin이 부르는 sync가
        // 이미 사라진 창을 또 닫으려 하지 않는다(재진입 차단).
        controller.willClose = { [weak self] in
            guard let self else { return }
            controllers[id] = nil
            onProjectWindowClosed?(id)
        }
        controller.onFrameChange = { [weak self] frame in self?.onFrameChange?(id, frame) }
        controllers[id] = controller
        controller.show()
        // 저장분이 없어 cascade로 자리를 잡은 창은 여기서 처음 좌표를 얻는다 — 모델에 즉시 새겨야
        // 다음 실행에서 같은 자리에 뜬다(windowDidMove는 사용자가 끌기 전엔 오지 않는다).
        controller.reportFrame()
    }

    /// 스크래치(~) 독립 창을 연다(생성/raise) — `sync`/`controllers`를 거치지 않는다.
    /// 이미 열려 있으면 앞으로만 올린다. 닫기는 `willClose`가 컨트롤러를 놓고 `onScratchClosed`(종료)를 알린다.
    /// 일회용이라 위치·크기는 지속하지 않는다 — 늘 기본 크기 + cascade로 뜬다.
    func openScratch(title: String) {
        if let c = scratchController { // 이미 열림 → raise만
            if c.window.isMiniaturized { c.window.deminiaturize(nil) }
            c.window.makeKeyAndOrderFront(nil)
            return
        }
        guard let content = makeScratchContent?() else { return }
        let c = MuxaWindowController(id: Scratch.windowId, content: content) // frame nil → cascade
        c.willClose = { [weak self] in self?.scratchController = nil; self?.onScratchClosed?() }
        scratchController = c
        c.window.title = title // '창' 메뉴에서 "~"로 식별
        c.show()
    }
}
