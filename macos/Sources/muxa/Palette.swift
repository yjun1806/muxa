import AppKit
import SwiftUI

/// 앱 크롬 색 팔레트 — 웹 `src/index.css`의 라이트 테마 값을 그대로 이식한다.
/// 웹이 `color-scheme: light` 고정이라 다크 대응 없이 단일 팔레트로 둔다(Tauri와 동일).
/// 색은 여기 한 곳에만 두고, AppKit/SwiftUI 어디서든 이 값을 참조한다(하드코딩 금지).
enum Palette {
    static let bg = NSColor(hex: 0xFFFFFF) // 콘텐츠·패인 배경
    static let panel = NSColor(hex: 0xF3F4F6) // 상단바·사이드바·패인 헤더(한 덩어리 회색)
    static let border = NSColor(hex: 0xE2E5E9)
    static let borderFocus = NSColor(hex: 0x0D9488) // 포커스·활성 강조(청록)
    static let muted = NSColor(hex: 0x6B7280)
    static let mutedHover = NSColor(hex: 0x1F2937)
    static let fg = NSColor(hex: 0x1F2937)
    static let btnHover = NSColor(hex: 0xE5E7EB)
    static let btnActive = NSColor(hex: 0xD1D5DB)
}

extension NSColor {
    /// 0xRRGGBB 정수로 sRGB 불투명 색을 만든다.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// SwiftUI에서 쓰는 팔레트 별칭 — NSColor 단일 진실을 그대로 감싼다.
extension Color {
    static let pBg = Color(nsColor: Palette.bg)
    static let pPanel = Color(nsColor: Palette.panel)
    static let pBorder = Color(nsColor: Palette.border)
    static let pBorderFocus = Color(nsColor: Palette.borderFocus)
    static let pMuted = Color(nsColor: Palette.muted)
    static let pFg = Color(nsColor: Palette.fg)
    static let pBtnHover = Color(nsColor: Palette.btnHover)
    static let pBtnActive = Color(nsColor: Palette.btnActive)
}
