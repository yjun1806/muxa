import AppKit
import Testing
@testable import muxa

/// 팔레트 힌트 → 메뉴 키 등가물(순수). 메뉴바 항목이 카탈로그의 단축키를 그대로 표시·실행하게 하는 다리.
struct MenuShortcutTests {
    @Test("⌘T는 t + command로 풀린다")
    func 단일수정자() {
        let key = MenuShortcut.parse("⌘T")
        #expect(key?.equivalent == "t")
        #expect(key?.modifiers == [.command])
    }

    @Test("⌘⇧D는 d + command·shift로 풀린다")
    func 복합수정자() {
        let key = MenuShortcut.parse("⌘⇧D")
        #expect(key?.equivalent == "d")
        #expect(key?.modifiers == [.command, .shift])
    }

    @Test("⌘ 없는 조합은 받지 않는다")
    func 커맨드없으면거부() {
        #expect(MenuShortcut.parse("⌃Tab") == nil)
    }

    @Test("키가 없거나 둘 이상이면 nil이다")
    func 잘못된힌트() {
        #expect(MenuShortcut.parse("⌘") == nil)
        #expect(MenuShortcut.parse("⌘AB") == nil)
        #expect(MenuShortcut.parse("") == nil)
    }

    @Test("카탈로그의 모든 힌트가 해석된다")
    func 카탈로그힌트전부해석() {
        for item in QuickCommandCatalog.items {
            guard let hint = item.shortcutHint else { continue }
            #expect(MenuShortcut.parse(hint) != nil, "해석 실패: \(hint)")
        }
    }
}
