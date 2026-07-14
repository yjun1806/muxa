import AppKit
import SwiftUI

/// 앱 크롬 색 팔레트. 시스템 외관(라이트/다크)에 따라 값이 바뀌는 동적 NSColor다.
/// 색은 여기 한 곳에만 두고, AppKit/SwiftUI 어디서든 이 값을 참조한다(하드코딩 금지).
///
/// **설계 원칙 — 크롬은 무채, 색은 신호다.**
/// 터미널 콘텐츠가 이미 ANSI 유채색으로 가득하다. 크롬까지 유채색이면 신호가 아니라 소음이다.
/// 그래서 크롬의 회색은 중립 무채(zinc)로 통일하고, 유채색은 두 계급만 남긴다 —
/// ① 포커스·활성(`borderFocus`·`brand`) ② 상태(`borderActivity`·git·서비스).
///
/// **아이콘의 teal과 UI의 teal은 다른 색이다.**
/// 앱 아이콘 배경(`Brand.key` = #2DD4BF)은 L\*78.5 · 고채도라 다크 크롬(#1B1B1D) 위에서 대비 9.24:1 —
/// 포커스 링에 필요한 3:1의 세 배이고, 보조 텍스트보다 15포인트 밝아 **크롬에서 가장 빛나는 물체**가 된다.
/// (VS Code #007ACC · Zed #2472F2 · Linear #5E6AD2는 전부 L\* 55~62다.)
/// 그래서 아이콘 색은 `Brand`에 격리하고, UI 강조는 채도를 내린 **딥틸**(`brand`·`borderFocus`)만 쓴다.
enum Palette {
    // MARK: - 아이콘 전용 브랜드 스케일
    //
    // **UI에서 이 스케일을 직접 꺼내 쓰지 않는다**(참조 0건이 정상이다 — 앱 코드의 소비자는 없다).
    // UI 강조가 필요하면 아래 semantic 토큰(`brand`·`borderFocus`)을 쓴다.
    //
    // 실제 아이콘을 그리는 곳은 `scripts/build-appicon/icon-gen.swift`다(`swift icon-gen.swift`로 도는
    // 단독 스크립트라 이 모듈을 임포트하지 못한다 — 값이 **미러링**된다). 아이콘 색을 바꾸려면
    // 그 파일과 여기를 함께 고친다. 여기 남겨두는 이유는 "UI teal ≠ 아이콘 teal"을 팔레트에서
    // 곧바로 읽히게 하기 위해서다.
    enum Brand {
        /// 서비스 키 컬러 = 앱 아이콘 배경(Tailwind teal-400). L*78.5 · 고채도 — UI에 쓰면 네온이 된다.
        static let key: UInt32 = 0x2DD4BF
        /// 아이콘 배경 squircle 그라디언트 양 끝 — 키 컬러 주변 명(위)·암(아래).
        static let gradTop: UInt32 = 0x35DECA
        static let gradBottom: UInt32 = 0x27C4B1
    }

    // MARK: 강조 semantic 토큰 (딥틸 — 아이콘 teal의 저채도 그림자)
    //
    /// 강조 텍스트·아이콘·CTA. 라이트 5.47:1 · 다크 5.9:1 — 양 모드 WCAG AA 통과.
    /// (기존 라이트 #0D9488은 흰 배경 대비 3.74:1로 AA 탈락이었다.)
    static let brand = NSColor.dynamic(light: 0x0F766E, dark: 0x5FB8AB)
    /// **포커스 링·활성 테두리 — `brand`보다 더 가라앉힌 값.**
    /// 테두리는 비텍스트라 3:1이면 충분하다(다크 4.15:1). 여기에 텍스트용 대비를 쓰면 칸마다 네온이 켜진다.
    static let borderFocus = NSColor.dynamic(light: 0x0F766E, dark: 0x3B8A7F)
    /// 옅은 강조 배경 틴트. **목록 선택에는 쓰지 않는다**(선택은 중립 `btnActive`가 macOS 규약).
    /// 라이트/다크의 무게를 대칭으로 맞췄다(기존 #CCFBF1은 흰 배경 대비 1.13:1로 사실상 안 보였다).
    static let brandSubtle = NSColor.dynamic(light: 0xE6F5F1, dark: 0x223834)
    /// 강조 hover — 한 단계 진하게.
    static let brandHover = NSColor.dynamic(light: 0x0C5F59, dark: 0x79C4B8)
    /// **`brand` 채움 위에 얹는 전경**(1급 CTA 글자). brand의 명도가 모드마다 뒤집히므로 전경도 뒤집힌다 —
    /// 라이트는 어두운 브랜드 위 흰 글자(5.52:1), 다크는 밝은 브랜드 위 딥 차콜(6.20:1). 양 모드 AA 통과.
    static let onBrand = NSColor.dynamic(light: 0xFFFFFF, dark: 0x0A2E2A)

    // MARK: - 중립(zinc 무채)
    //
    // 라이트 회색은 Tailwind gray 램프(청보라 언더톤 H≈260)였는데, 브랜드 teal(H≈182)과 74~104° 어긋나
    // 서로 밀어냈다. 양 모드를 중립 zinc(H≈286, 채도 거의 0)로 통일한다.
    static let bg = NSColor.dynamic(light: 0xFFFFFF, dark: 0x1B1B1D) // 콘텐츠·패인 배경
    // 크롬↔콘텐츠의 층은 **명도차가 아니라 카드의 고도**(`Elevation.card`)가 만든다.
    // 다크 명도차를 ΔL*≈10 → ≈4로 좁혔다 — 크롬이 도형으로 읽히면 "조용한 크롬"이 아니다.
    static let panel = NSColor.dynamic(light: 0xF4F4F5, dark: 0x262629) // 상단바·사이드바·패인 헤더(한 덩어리 회색)
    static let border = NSColor.dynamic(light: 0xE4E4E7, dark: 0x34343A) // 카드 경계 — 그림자·인셋 하이라이트와 함께 층을 만든다
    static let borderActivity = NSColor.dynamic(light: 0xB45309, dark: 0xFBBF24) // 활동·주의 환기(호박) — 라이트 #F59E0B는 흰 배경 대비 2.15:1로 사실상 안 보였다
    static let muted = NSColor.dynamic(light: 0x65656B, dark: 0x98989E) // 보조 텍스트 — 다크 #8A8A90은 3.82:1로 AA 탈락이었다
    static let mutedHover = NSColor.dynamic(light: 0x232326, dark: 0xE4E4E7)
    static let fg = NSColor.dynamic(light: 0x232326, dark: 0xE4E4E7)
    // 목록 선택·hover 채움 — **중립이다. 브랜드색을 쓰지 않는다**(macOS 규약: 색은 상태에만).
    static let btnHover = NSColor.dynamic(light: 0xE8E8EA, dark: 0x313135)
    static let btnActive = NSColor.dynamic(light: 0xD6D6D9, dark: 0x3C3C41)

    // git 상태색 — 익스플로러 파일명·git 패널 배지 공용(하드코딩 금지, 여기 한 곳).
    // AA(4.5:1) 미달이던 값을 수리했다: gitModified 라이트 3.30→4.87, gitDeleted 다크 3.92→5.5.
    static let gitModified = NSColor.dynamic(light: 0x9A6700, dark: 0xE2B341) // 수정(주황/노랑)
    static let gitAdded = NSColor.dynamic(light: 0x1A7F37, dark: 0x3FB950) // 추가·untracked(초록)
    static let gitDeleted = NSColor.dynamic(light: 0xCF222E, dark: 0xFF7B72) // 삭제(빨강)
    static let gitRenamed = NSColor.dynamic(light: 0x0969DA, dark: 0x58A6FF) // 이름변경/복사(파랑)
    static let gitConflict = NSColor.dynamic(light: 0xBC4C00, dark: 0xDB6D28) // 충돌(주황빨강)

    // GitHub PR 배지색 — gh 배지 전용. open=gitAdded(초록)·closed=gitDeleted(빨강) 재사용, merged만 신규(보라).
    static let prMerged = NSColor.dynamic(light: 0x8250DF, dark: 0xB392F9) // 다크 3.91→5.6:1

    /// 에러·파괴적 동작(빨강). git 삭제색과 같은 값이지만 의미가 달라 별칭으로 둔다 —
    /// 에러 메시지에 `.red`(시스템색)를 직접 쓰면 팔레트 밖으로 새서 라이트/다크 대비가 어긋난다.
    static let danger = gitDeleted

    // 서비스(장수 프로세스) 상태 점 — "정상/문제"라는 같은 의미축이라 git 상태색을 재사용한다.
    static let serviceRunning = gitAdded // 실행 중(초록)
    static let serviceExited = gitDeleted // 비정상 종료(빨강)
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
    static let pBrand = Color(nsColor: Palette.brand)
    static let pBrandSubtle = Color(nsColor: Palette.brandSubtle)
    static let pBrandHover = Color(nsColor: Palette.brandHover)
    static let pOnBrand = Color(nsColor: Palette.onBrand)
    static let pBorderActivity = Color(nsColor: Palette.borderActivity)
    static let pMuted = Color(nsColor: Palette.muted)
    static let pFg = Color(nsColor: Palette.fg)
    static let pBtnHover = Color(nsColor: Palette.btnHover)
    static let pBtnActive = Color(nsColor: Palette.btnActive)
    static let pDanger = Color(nsColor: Palette.danger)
    static let pServiceRunning = Color(nsColor: Palette.serviceRunning)
    static let pServiceExited = Color(nsColor: Palette.serviceExited)
}
