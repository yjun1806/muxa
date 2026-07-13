import AppKit
import GhosttyKit

/// 터미널 서피스의 마우스 입력 — AppKit 이벤트를 libghostty에 밀어 넣는다.
///
/// libghostty는 자기 NSView를 갖지 않는다. 위치·버튼·스크롤을 우리가 넘겨줘야만 코어가 안다
/// (안 넘기면 드래그 선택·클릭 위치 지정·마우스 리포팅 앱의 클릭이 전부 죽는다).
///
/// **"터미널이 먹을까, 앱이 먹을까"는 추측하지 않고 코어에 묻는다** — `ghostty_surface_mouse_captured`.
/// 마우스 리포팅을 켠 앱(vim·tmux·claude code)이 돌고 있으면 우클릭은 그 앱의 것이고,
/// 아니면 앱 컨텍스트 메뉴를 띄운다. 이 한 갈래가 우클릭 정책의 단일 진실 원천이다. (cmux 구조)
extension TermView {
    /// 터미널이 마우스를 캡처했는가 = 안에서 도는 앱이 마우스 이벤트를 직접 쓰고 있는가.
    var mouseCaptured: Bool {
        guard let surface else { return false }
        return ghostty_surface_mouse_captured(surface)
    }

    // MARK: 버튼

    override func mouseDown(with event: NSEvent) {
        let wasFocused = isFocused
        window?.makeFirstResponder(self)
        onFocus?()

        // 포커스 이전 클릭은 터미널에 넘기지 않는다 — 다른 칸을 눌러 포커스만 옮기려는 클릭이
        // 텍스트 선택을 시작하거나 TUI 앱에 클릭으로 꽂히면 안 된다(cmux 포커스 정책).
        // press를 삼켰으므로 pendingLeftRelease가 false로 남아 대응 release도 자동으로 안 나간다.
        guard wasFocused else { return }

        // 위치 동기화는 단일 클릭에만. 더블/트리플 클릭(단어·줄 선택) 중에 위치를 다시 밀어 넣으면
        // 코어가 선택 확장을 새 클릭으로 오인해 선택이 깨진다.
        if event.clickCount == 1 { syncMousePos(with: event) }
        _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, event)
        pendingLeftRelease = true
    }

    override func mouseUp(with event: NSEvent) {
        // press를 넘긴 적 없으면 release도 넘기지 않는다(짝 보장).
        guard pendingLeftRelease else { return }
        pendingLeftRelease = false
        syncMousePos(with: event)
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        syncMousePos(with: event)

        // 터미널 안의 앱이 마우스를 쓰고 있으면 우클릭은 그 앱의 것이다.
        if mouseCaptured {
            _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event)
            return
        }

        // 앱 메뉴를 띄우기 전에 우클릭 press를 한 번 보낸다 — 코어가 이 위치를 기준으로 선택 상태를
        // 갱신하게 해서, "우클릭한 곳의 선택"과 메뉴의 복사 동작이 어긋나지 않게 한다(cmux).
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT,
                                         ghosttyMods(event.modifierFlags))
        onContextMenu?(NSEvent.mouseLocation)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard mouseCaptured else { return } // 메뉴 경로에선 release를 보내지 않는다(press만 선택 갱신용)
        syncMousePos(with: event)
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event)
    }

    // 가운데 버튼(=2)만 터미널에 넘긴다(붙여넣기). 4·5번(뒤로/앞으로)은 터미널이 쓰지 않으므로
    // 가운데로 오전송하지 않고 AppKit 기본 처리에 맡긴다(cmux).
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        syncMousePos(with: event)
        _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseUp(with: event) }
        syncMousePos(with: event)
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, event)
    }

    /// 코어가 이 버튼 이벤트를 소비했으면 true.
    @discardableResult
    private func sendMouseButton(_ state: ghostty_input_mouse_state_e,
                                 _ button: ghostty_input_mouse_button_e,
                                 _ event: NSEvent) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_mouse_button(surface, state, button, ghosttyMods(event.modifierFlags))
    }

    // MARK: 위치
    //
    // libghostty는 마우스 리포팅을 켠 앱(claude code 등, DECSET 1000/1002)에는 스크롤을
    // "현재 커서 위치의 버튼 4/5 이벤트"로 변환해 보낸다. 위치를 한 번도 안 알려주면 embedded
    // cursor_pos가 초기값 (-1,-1)에 머물러 리포트가 통째로 버려지고 뷰포트 스크롤도 건너뛴다.

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 이벤트 좌표를 ghostty 좌표계(좌상단 원점)로 변환해 서피스에 알린다.
    func syncMousePos(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) { syncMousePos(with: event) }
    override func mouseEntered(with event: NSEvent) { syncMousePos(with: event) }
    override func mouseDragged(with event: NSEvent) { syncMousePos(with: event) }
    override func rightMouseDragged(with event: NSEvent) { syncMousePos(with: event) }
    override func otherMouseDragged(with event: NSEvent) { syncMousePos(with: event) }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        // 드래그 중 이탈은 위치를 유지한다 — 선택 오토스크롤이 "뷰포트 밖 포인터"를 관측해야 한다.
        if NSEvent.pressedMouseButtons != 0 { return }
        ghostty_surface_mouse_pos(surface, -1, -1, ghosttyMods(event.modifierFlags))
    }

    // MARK: 스크롤
    //
    // 정밀 델타(트랙패드)는 precision 비트(0x1)로, 모멘텀 페이즈는 상위 비트로 인코딩한다.

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        // 트래킹 이벤트를 아직 못 받았어도(부착 직후 커서가 이미 뷰 안 등) 스크롤 이벤트 자신의
        // 좌표로 위치를 확정한다 — 마우스 리포팅 앱으로의 스크롤 변환이 위치에 의존하기 때문.
        syncMousePos(with: event)
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY

        var mods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            mods = 1 // precision(픽셀 단위 트랙패드)
            x *= 2 // 체감 속도 보정 — 업스트림과 동일한 2배
            y *= 2
        }

        var momentum = GHOSTTY_MOUSE_MOMENTUM_NONE
        switch event.momentumPhase {
        case .began: momentum = GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: momentum = GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: momentum = GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: momentum = GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: momentum = GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: momentum = GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: break
        }
        mods |= ghostty_input_scroll_mods_t(momentum.rawValue) << 1

        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    // MARK: 커서 모양·가시성 (MOUSE_SHAPE / MOUSE_VISIBILITY 액션)
    //
    // 엔진이 "지금 커서는 이 모양"이라고 알려준다(텍스트 위 I-beam, 링크 위 손가락, resize 등).
    // 안 받으면 커서가 영원히 화살표로 남는다. 커서 렉트로 적용해 AppKit이 영역 진입 시 자동으로 세운다.

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: mouseShape)
    }

    /// 엔진이 요청한 커서 모양을 NSCursor로 옮긴다. macOS에 대응 커서가 없는 모양은 가장 가까운 것으로.
    func setMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        mouseShape = TermView.cursor(for: shape)
    }

    /// 타이핑 중 커서 숨김 — 마우스를 움직이면 자동으로 다시 나타난다.
    func setMouseVisibility(_ visible: Bool) {
        NSCursor.setHiddenUntilMouseMoves(!visible)
    }

    private static func cursor(for shape: ghostty_action_mouse_shape_e) -> NSCursor {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: return .arrow
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_CELL: return .iBeam
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: return .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_POINTER: return .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: return .crosshair
        case GHOSTTY_MOUSE_SHAPE_GRAB: return .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING, GHOSTTY_MOUSE_SHAPE_ALL_SCROLL: return .closedHand
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP: return .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_ALIAS: return .dragLink
        case GHOSTTY_MOUSE_SHAPE_COPY: return .dragCopy
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: return .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE,
             GHOSTTY_MOUSE_SHAPE_E_RESIZE, GHOSTTY_MOUSE_SHAPE_W_RESIZE:
            return .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE,
             GHOSTTY_MOUSE_SHAPE_N_RESIZE, GHOSTTY_MOUSE_SHAPE_S_RESIZE:
            return .resizeUpDown
        default: return .arrow // 대각 resize·zoom 등 — macOS 공개 커서에 대응이 없다
        }
    }
}
