import AppKit
import Carbon
import GhosttyKit

/// 터미널 서피스 NSView — libghostty가 이 뷰에 Metal 레이어를 붙여 직접 렌더한다.
///
/// 키 입력·IME는 Ghostty 업스트림 SurfaceView_AppKit.swift(MIT)의 검증된 구현을 이식했다.
/// 핵심 계약: keyDown → interpretKeyEvents → (insertText | setMarkedText) 순서로 AppKit이
/// IME를 구동하고, 우리는 marked text를 ghostty_surface_preedit로, 확정 텍스트를
/// ghostty_surface_key(text:)로 내려보낸다. 조합 미리보기는 libghostty가 커서 위치에 그린다.
final class TermView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?

    /// IME 조합 중(preedit) 텍스트. NSTextInputClient가 채운다.
    private var markedText = NSMutableAttributedString()

    /// keyDown 동안 insertText가 확정한 텍스트를 모은다 (한국어 등 복합 입력).
    /// non-nil이면 "지금 keyDown 처리 중"이라는 신호다.
    private var keyTextAccumulator: [String]? = nil

    override var acceptsFirstResponder: Bool { true }

    init(app: ghostty_app_t) {
        super.init(frame: .zero)

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        self.surface = ghostty_surface_new(app, &config)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    // MARK: 크기·스케일 — 백킹 픽셀 단위로 전달 (업스트림 계약)

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncScaleAndSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncScaleAndSize()
    }

    private func syncScaleAndSize() {
        guard let surface, frame.width > 0, frame.height > 0 else { return }
        let backing = convertToBacking(frame)
        let xScale = backing.size.width / frame.size.width
        let yScale = backing.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(surface, UInt32(backing.size.width), UInt32(backing.size.height))
    }

    // MARK: 포커스

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        syncScaleAndSize()
    }

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    // MARK: 키 입력 — Ghostty SurfaceView_AppKit.keyDown 이식

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // option-as-alt 등 번역 모디파이어 계산 (업스트림 계약: 같으면 원본 이벤트 재사용 —
        // AppKit 내부의 객체 동일성 때문에 한국어 입력이 여기 걸려 있다)
        let translationModsGhostty = eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(surface, ghosttyMods(event.modifierFlags))
        )
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // interpretKeyEvents가 insertText/setMarkedText를 부른다 — 그 결과를 모은다
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0

        // 한영 전환(Shift+Space 등) 키가 자판을 바꿨다면 그 키는 터미널로 보내지 않는다
        let keyboardIdBefore: String? = markedTextBefore ? nil : KeyboardLayout.id

        interpretKeyEvents([translationEvent])

        if !markedTextBefore && keyboardIdBefore != KeyboardLayout.id {
            return
        }

        // 조합 상태를 libghostty에 동기화 — 미리보기는 엔진이 커서 위치에 그린다
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            // 조합이 확정한 텍스트 — composing=false로 전송
            for text in list {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            _ = keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters,
                // 조합 중이거나(조합 취소 직후 포함) 그 키는 인코딩하면 안 된다
                composing: markedText.length > 0 || markedTextBefore
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// 비프음 방지 + AppKit 셀렉터 디스패치 흡수 (인코딩은 keyAction이 담당)
    override func doCommand(by selector: Selector) {}

    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = ghosttyKeyEvent(event, action: action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing

        // 제어문자(0x20 미만)는 Ghostty가 자체 인코딩한다 — text로 보내지 않는다
        if let text, !text.isEmpty, let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    // MARK: NSTextInputClient — Ghostty 업스트림 이식

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(0...(markedText.length - 1))
    }

    func selectedRange() -> NSRange { NSRange() }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: break
        }
        // keyDown 밖에서 온 조합 변경(자판 전환 중 조합 등)은 즉시 동기화
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    /// IME 후보창 위치 — libghostty가 커서 픽셀 좌표를 알려준다
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        // Ghostty 좌표계는 좌상단 원점 — AppKit 좌하단으로 변환
        let viewRect = NSRect(x: x, y: frame.size.height - y, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil, let surface else { return }

        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }

        // insertText가 불렸다는 건 조합이 끝났다는 뜻
        unmarkText()

        // keyDown 처리 중이면 모아서 keyDown이 전송하게 한다
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }

        // keyDown 밖(딕테이션 등)에서 온 텍스트는 직접 전송
        let len = chars.utf8CString.count
        if len > 1 {
            chars.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }
    }

    /// markedText 상태를 libghostty preedit로 동기화
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - 헬퍼 (Ghostty.Input.swift · NSEvent+Extension.swift 이식)

/// NSEvent 모디파이어 → ghostty mods
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
    return ghostty_input_mods_e(mods)
}

/// ghostty mods → NSEvent 모디파이어 (역변환)
func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags(rawValue: 0)
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
    return flags
}

/// NSEvent → ghostty_input_key_s (text·composing 제외 — 수명 문제로 호출부가 채운다)
func ghosttyKeyEvent(
    _ event: NSEvent,
    action: ghostty_input_action_e,
    translationMods: NSEvent.ModifierFlags? = nil
) -> ghostty_input_key_s {
    var keyEvent = ghostty_input_key_s()
    keyEvent.action = action
    keyEvent.keycode = UInt32(event.keyCode)
    keyEvent.text = nil
    keyEvent.composing = false
    keyEvent.mods = ghosttyMods(event.modifierFlags)
    // ctrl·cmd는 텍스트 번역에 기여하지 않는다는 업스트림 휴리스틱
    keyEvent.consumed_mods = ghosttyMods(
        (translationMods ?? event.modifierFlags).subtracting([.control, .command])
    )
    keyEvent.unshifted_codepoint = 0
    if event.type == .keyDown || event.type == .keyUp {
        if let chars = event.characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        }
    }
    return keyEvent
}

extension NSEvent {
    /// 제어문자·PUA(펑션키)를 걸러낸 전송용 문자 (업스트림 이식)
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}

/// 현재 키보드 입력 소스 ID — 한영 전환 키 감지에 사용 (업스트림 이식)
enum KeyboardLayout {
    static var id: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
