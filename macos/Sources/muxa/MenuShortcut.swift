import AppKit

/// 팔레트 단축키 힌트("⌘⇧D") → NSMenuItem 키 등가물 판정(순수).
///
/// 명령 목록과 그 단축키의 단일 출처는 `QuickCommandCatalog`다 — 메뉴바는 그 힌트를 그대로 읽어
/// 항목을 굽는다(같은 표를 두 번 적지 않는다). 힌트가 없거나 해석 못 하는 조합이면 nil(단축키 없이 표시).
enum MenuShortcut {
    struct Key: Equatable {
        let equivalent: String                 // NSMenuItem.keyEquivalent (소문자 1글자)
        let modifiers: NSEvent.ModifierFlags   // NSMenuItem.keyEquivalentModifierMask
    }

    /// ⌘가 없는 조합은 받지 않는다 — 메뉴 키 등가물이 터미널 평문 입력을 가로채면 안 된다.
    static func parse(_ hint: String) -> Key? {
        var modifiers: NSEvent.ModifierFlags = []
        var key = ""
        for ch in hint {
            switch ch {
            case "⌘": modifiers.insert(.command)
            case "⇧": modifiers.insert(.shift)
            case "⌥": modifiers.insert(.option)
            case "⌃": modifiers.insert(.control)
            default: key += ch.lowercased()
            }
        }
        guard key.count == 1, modifiers.contains(.command) else { return nil }
        return Key(equivalent: key, modifiers: modifiers)
    }
}
