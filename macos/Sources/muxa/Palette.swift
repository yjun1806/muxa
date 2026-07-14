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
    // MARK: - 브랜드 키 컬러 (muxa teal)
    //
    // 서비스 키 컬러 = 앱 아이콘 배경색인 teal. 강조·포커스·CTA·선택의 단일 출처다.
    // Tailwind teal 계열의 지각 균등 스케일을 채택했고, **키 컬러는 `Brand.key`(= 400)**.
    // 아이콘 배경은 이 400 주변 명암 그라디언트(`gradTop`↔`gradBottom`)로 칠한다.
    // 새 강조색이 필요하면 이 스케일에서 고르고, 하드코딩하지 않는다.
    enum Brand {
        static let s50: UInt32 = 0xF0FDFA
        static let s100: UInt32 = 0xCCFBF1
        static let s200: UInt32 = 0x99F6E4
        static let s300: UInt32 = 0x5EEAD4
        static let s400: UInt32 = 0x2DD4BF // ★ 키 컬러 (앱 아이콘 배경)
        static let s500: UInt32 = 0x14B8A6
        static let s600: UInt32 = 0x0D9488
        static let s700: UInt32 = 0x0F766E
        static let s800: UInt32 = 0x115E59
        static let s900: UInt32 = 0x134E4A

        /// 서비스 키 컬러(= 400). 아이콘 배경·브랜드 강조의 기준값.
        static let key: UInt32 = s400
        /// 아이콘 배경 squircle 그라디언트 양 끝 — 키 컬러 주변 명(위)·암(아래).
        static let gradTop: UInt32 = 0x35DECA
        static let gradBottom: UInt32 = 0x27C4B1
    }

    // MARK: 브랜드 semantic 토큰 (키 컬러 파생)
    //
    /// 브랜드 강조 — 포커스·활성·선택·CTA. 라이트는 대비 위해 s600, 다크는 키 s400.
    /// (`borderFocus`가 이 토큰의 별칭 — 브랜드 스케일이 강조색의 단일 출처다.)
    static let brand = NSColor.dynamic(light: Brand.s600, dark: Brand.s400)
    /// 브랜드 배경 틴트 — 옅은 강조 배경·선택 하이라이트(키 컬러의 저채도 버전).
    static let brandSubtle = NSColor.dynamic(light: Brand.s100, dark: Brand.s800)
    /// 브랜드 강조 hover — 한 단계 진하게(라이트 s700, 다크 s300).
    static let brandHover = NSColor.dynamic(light: Brand.s700, dark: Brand.s300)
    /// 키 컬러(밝은 청록) 위에 얹는 전경 — 아이콘 심볼과 같은 딥 차콜. 텍스트·아이콘 on-brand.
    static let onBrand = NSColor.dynamic(light: 0x0A2E2A, dark: 0x0A2E2A)

    // MARK: - 중립·기능색
    static let bg = NSColor.dynamic(light: 0xFFFFFF, dark: 0x1B1B1D) // 콘텐츠·패인 배경
    // 크롬(바깥)은 콘텐츠·터미널(안)과 뚜렷이 갈려야 층이 읽힌다. 예전엔 라이트 F3F4F6·다크 252528로
    // 근접해, 근백색·근흑색 터미널과 한 톤으로 뭉갰다. 양쪽 다 크롬을 한 단계 밀어 명도차를 벌렸다
    // (라이트 F3F4F6→E7EAEE 진하게 / 다크 252528→303035 밝게).
    static let panel = NSColor.dynamic(light: 0xE7EAEE, dark: 0x303035) // 상단바·사이드바·패인 헤더(한 덩어리 회색)
    static let border = NSColor.dynamic(light: 0xD5D9DF, dark: 0x48484E) // 카드 경계 — 크롬↔콘텐츠 층을 또렷하게
    static let borderFocus = brand // 포커스·활성 강조 = 브랜드 키 컬러(브랜드 스케일 단일 출처)
    static let borderActivity = NSColor.dynamic(light: 0xF59E0B, dark: 0xFBBF24) // 칸 활동 플래시(주황) — focus(청록)와 구분되는 주의 환기색
    static let muted = NSColor.dynamic(light: 0x6B7280, dark: 0x8A8A90)
    static let mutedHover = NSColor.dynamic(light: 0x1F2937, dark: 0xE4E4E7)
    static let fg = NSColor.dynamic(light: 0x1F2937, dark: 0xE4E4E7)
    static let btnHover = NSColor.dynamic(light: 0xE5E7EB, dark: 0x37373B)
    static let btnActive = NSColor.dynamic(light: 0xD1D5DB, dark: 0x47474C)

    /// 포커스 없는 칸에 덮는 베일 — **"지금 입력이 어디로 가는가"를 밝기로 말한다**(테두리 대신).
    ///
    /// 테두리는 상시 켜지면 강조를 잃는다. 같은 테두리 채널을 에이전트 알림(주황)이 쓰는데,
    /// 청록 테두리가 늘 깔려 있으면 정작 나를 부르는 주황이 그 위에서 경쟁해야 한다.
    /// 밝기로 말하면 테두리가 비고, **테두리가 뜨면 그건 진짜 알림이다**.
    ///
    /// **약하게 잡는다** — 칸을 나란히 놓고 두 터미널을 대조하는 게 이 앱의 일상이다.
    /// 안 보이는 칸을 만들면 분할의 의미가 없다. 알아볼 수 있을 만큼만 눌러 둔다.
    /// (다크가 라이트보다 진한 건 어두운 배경에서 같은 알파가 훨씬 덜 보이기 때문이다.)
    static let paneVeil = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: 0, alpha: isDark ? 0.12 : 0.03)
    }

    // git 상태색 — 익스플로러 파일명·git 패널 배지 공용(하드코딩 금지, 여기 한 곳).
    static let gitModified = NSColor.dynamic(light: 0xB08800, dark: 0xE2B341) // 수정(주황/노랑)
    static let gitAdded = NSColor.dynamic(light: 0x1A7F37, dark: 0x3FB950) // 추가·untracked(초록)
    static let gitDeleted = NSColor.dynamic(light: 0xCF222E, dark: 0xF85149) // 삭제(빨강)
    static let gitRenamed = NSColor.dynamic(light: 0x0969DA, dark: 0x58A6FF) // 이름변경/복사(파랑)
    static let gitConflict = NSColor.dynamic(light: 0xBC4C00, dark: 0xDB6D28) // 충돌(주황빨강)

    // GitHub PR 배지색 — gh 배지 전용. open=gitAdded(초록)·closed=gitDeleted(빨강) 재사용, merged만 신규(보라).
    static let prMerged = NSColor.dynamic(light: 0x8250DF, dark: 0xA371F7)

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
    static let pPaneVeil = Color(nsColor: Palette.paneVeil)
    static let pMuted = Color(nsColor: Palette.muted)
    static let pFg = Color(nsColor: Palette.fg)
    static let pBtnHover = Color(nsColor: Palette.btnHover)
    static let pBtnActive = Color(nsColor: Palette.btnActive)
    static let pDanger = Color(nsColor: Palette.danger)
    static let pServiceRunning = Color(nsColor: Palette.serviceRunning)
    static let pServiceExited = Color(nsColor: Palette.serviceExited)
}
