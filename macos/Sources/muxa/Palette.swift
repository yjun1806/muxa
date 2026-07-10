import AppKit
import SwiftUI

/// 앱 크롬 색 팔레트 — 라이트 값은 웹 `src/index.css`에서 이식하고, 다크 값은 macOS 관례에 맞춰 새로 잡는다.
/// 색은 시스템 외관(라이트/다크)에 따라 자동으로 값이 바뀌는 동적 NSColor다.
/// 색은 여기 한 곳에만 두고, AppKit/SwiftUI 어디서든 이 값을 참조한다(하드코딩 금지).
///
/// 다크 값 결정 근거(웹엔 다크 원본이 없어 새로 잡음):
/// - 라이트에선 크롬(panel)이 배경(bg)보다 어둡지만, 다크에선 반대로 크롬이 배경보다 밝아야 층이 구분된다.
/// - 회색 스케일은 Tailwind zinc/neutral 계열의 어두운 톤에 대응시킨다.
/// - 강조(borderFocus)는 어두운 배경에서 잘 보이도록 라이트보다 밝은 청록으로 올린다.
enum Palette {
    static let bg = NSColor.dynamic(light: 0xFFFFFF, dark: 0x1B1B1D) // 콘텐츠·패인 배경
    static let panel = NSColor.dynamic(light: 0xF3F4F6, dark: 0x252528) // 상단바·사이드바·패인 헤더(한 덩어리 회색)
    static let border = NSColor.dynamic(light: 0xE2E5E9, dark: 0x38383C)
    static let borderFocus = NSColor.dynamic(light: 0x0D9488, dark: 0x2DD4BF) // 포커스·활성 강조(청록)
    static let borderActivity = NSColor.dynamic(light: 0xF59E0B, dark: 0xFBBF24) // 칸 활동 플래시(주황) — focus(청록)와 구분되는 주의 환기색
    static let muted = NSColor.dynamic(light: 0x6B7280, dark: 0x8A8A90)
    static let mutedHover = NSColor.dynamic(light: 0x1F2937, dark: 0xE4E4E7)
    static let fg = NSColor.dynamic(light: 0x1F2937, dark: 0xE4E4E7)
    static let btnHover = NSColor.dynamic(light: 0xE5E7EB, dark: 0x37373B)
    static let btnActive = NSColor.dynamic(light: 0xD1D5DB, dark: 0x47474C)

    // git 상태색 — 익스플로러 파일명·git 패널 배지 공용(하드코딩 금지, 여기 한 곳).
    static let gitModified = NSColor.dynamic(light: 0xB08800, dark: 0xE2B341) // 수정(주황/노랑)
    static let gitAdded = NSColor.dynamic(light: 0x1A7F37, dark: 0x3FB950) // 추가·untracked(초록)
    static let gitDeleted = NSColor.dynamic(light: 0xCF222E, dark: 0xF85149) // 삭제(빨강)
    static let gitRenamed = NSColor.dynamic(light: 0x0969DA, dark: 0x58A6FF) // 이름변경/복사(파랑)
    static let gitConflict = NSColor.dynamic(light: 0xBC4C00, dark: 0xDB6D28) // 충돌(주황빨강)

    // GitHub PR 배지색 — gh 배지 전용. open=gitAdded(초록)·closed=gitDeleted(빨강) 재사용, merged만 신규(보라).
    static let prMerged = NSColor.dynamic(light: 0x8250DF, dark: 0xA371F7)
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

    /// 시스템 외관(라이트/다크)에 따라 값이 자동으로 바뀌는 동적 색.
    /// SwiftUI(`Color(nsColor:)`)·NSWindow.backgroundColor·contentTintColor는 이 색을 자동 재해결한다.
    /// 단, `layer.backgroundColor`처럼 `.cgColor`로 굳는 곳은 updateLayer/draw에서 다시 칠해야 한다.
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

/// SwiftUI에서 쓰는 팔레트 별칭 — NSColor 단일 진실을 그대로 감싼다(동적 색이라 라이트/다크 자동 반응).
extension Color {
    static let pBg = Color(nsColor: Palette.bg)
    static let pPanel = Color(nsColor: Palette.panel)
    static let pBorder = Color(nsColor: Palette.border)
    static let pBorderFocus = Color(nsColor: Palette.borderFocus)
    static let pBorderActivity = Color(nsColor: Palette.borderActivity)
    static let pMuted = Color(nsColor: Palette.muted)
    static let pFg = Color(nsColor: Palette.fg)
    static let pBtnHover = Color(nsColor: Palette.btnHover)
    static let pBtnActive = Color(nsColor: Palette.btnActive)
}
