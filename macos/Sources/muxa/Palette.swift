import AppKit
import SwiftUI

/// 앱 크롬 색 팔레트. 시스템 외관(라이트/다크)에 따라 값이 바뀌는 동적 NSColor다.
/// 색은 여기 한 곳에만 두고, AppKit/SwiftUI 어디서든 이 값을 참조한다(하드코딩 금지).
///
/// **설계 원칙 — 크롬은 무채, 색은 신호다.**
/// 터미널 콘텐츠가 이미 ANSI 유채색으로 가득하다. 크롬까지 유채색이면 신호가 아니라 소음이다.
/// 그래서 크롬의 회색은 중립 무채(zinc)로 통일하고, 유채색은 두 계급만 남긴다 —
/// ① 포커스·활성(`brand`) ② 상태(`borderActivity`·git·서비스).
///
/// **포커스는 색이 아니라 밝기로 말한다**(D20). 칸 포커스 링(`borderFocus`)은 없앴다 —
/// 포커스 없는 칸에 `paneVeil`을 덮고, 테두리 채널은 **에이전트 알림(`borderActivity`)에만** 내준다.
/// 테두리가 뜨면 그건 진짜 알림이다. 남은 포커스 강조는 선택 탭의 `brand` 지시선 하나뿐이다.
///
/// **아이콘의 teal과 UI의 teal은 다른 색이다.**
/// 앱 아이콘 배경(`Brand.key` = #2DD4BF)은 L\*78.5 · 고채도라 다크 크롬(#1B1B1D) 위에서 대비 9.24:1 —
/// 포커스 링에 필요한 3:1의 세 배이고, 보조 텍스트보다 15포인트 밝아 **크롬에서 가장 빛나는 물체**가 된다.
/// (VS Code #007ACC · Zed #2472F2 · Linear #5E6AD2는 전부 L\* 55~62다.)
/// 그래서 아이콘 색은 `Brand`에 격리하고, UI 강조는 채도를 내린 **딥틸**(`brand`)만 쓴다.
enum Palette {
    // MARK: - 아이콘 전용 브랜드 스케일
    //
    // **UI에서 이 스케일을 직접 꺼내 쓰지 않는다**(참조 0건이 정상이다 — 앱 코드의 소비자는 없다).
    // UI 강조가 필요하면 아래 semantic 토큰(`brand`)을 쓴다.
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
    ///
    /// **포커스 지시선(선택 탭 하단)도 이 토큰이다** — 한때 `borderFocus`(다크 #3B8A7F)라는 더 가라앉힌
    /// 테두리 전용 값을 뒀지만, 지시선이 사는 면은 `bg`가 아니라 **탭바(`btnActive`)**다.
    /// 거기서 #3B8A7F는 2.26:1로 비텍스트 3:1에도 못 미치고, `brand`는 3.93:1로 통과한다.
    /// 유일한 소비자였던 칸 포커스 링이 D20(→ `paneVeil`)으로 사라진 데다 지시선도 못 맡으니 토큰을 지웠다.
    static let brand = NSColor.dynamic(light: 0x0F766E, dark: 0x5FB8AB)
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
    // **크롬↔콘텐츠의 층은 명도차 *하나로만* 만들지 않는다 — 카드 고도(`Elevation.Card`)와 나눠 진다.**
    //
    // 두 주장이 정면으로 부딪혔고, 둘 다 부분적으로 옳았다:
    // ① "명도차를 벌려라"(ccb8d68) — 근백색·근흑색 터미널과 크롬이 한 톤으로 뭉갰다. 증상은 진짜다.
    // ② "크롬은 조용해야 한다"(팔레트 수술) — 명도차로만 메우면 크롬 자체가 도형으로 읽힌다.
    //
    // 카드 고도(그림자 + 다크 상단 인셋 하이라이트)가 새 신호를 주지만, **닿는 경계가 한정된다** —
    // 사이드바·상단바↔카드에는 닿고, **카드 *안*의 도구 패널(익스플로러·git)↔터미널 경계에는 안 닿는다**
    // (거긴 `panel`과 `bg`가 `border` 선 하나를 두고 직접 맞닿는다). 그 경계엔 명도차 말고 대안이 없다.
    // 그래서 명도차를 0으로 되돌리지 않고 **두 값의 중간**에 둔다 — 고도가 덜어준 만큼만 뺀다.
    //   다크 ΔL*: 10.2(ccb8d68) → 5.4(수술안) → **7.8(여기)**  /  라이트: 7.4 → 3.8 → **5.5**
    // 색상은 zinc 무채를 유지한다(위 주석) — 되돌린 건 명도지 색상이 아니다.
    static let panel = NSColor.dynamic(light: 0xEFEFF1, dark: 0x2B2B2F) // 상단바·사이드바·패인 헤더(한 덩어리 회색)
    // 카드 경계이자 **카드 안의 패널↔터미널 분할선**. 고도가 못 닿는 그 선이 유일한 신호라 함께 올렸다
    // (다크 34343A→3E3E44: bg 대비 1.39→1.62, panel 대비 1.14→1.33).
    static let border = NSColor.dynamic(light: 0xDCDCE0, dark: 0x3E3E44)
    // 사이드바 2단 트리의 **세로 가이드선** — 프로젝트를 그 워크스페이스 아래로 묶어 소속을 그린다.
    // 1px가 panel 위에서 읽혀야 하므로 border보다 살짝 진하게 잡는다(다크 3E3E44는 panel 대비 안 보였다 → 54545C).
    static let guide = NSColor.dynamic(light: 0xCBCBD2, dark: 0x54545C)
    // 활동·주의 환기(호박). 라이트를 B45309(적갈색)→A16207(앰버/머스터드)로 옮겼다 — 적갈색이 실패색
    // #CF222E(빨강)와 헷갈렸다(에러처럼 읽힘). A16207은 초록 채널이 살아 확실한 앰버고 흰 배경 대비 4.9:1(AA).
    // (#F59E0B는 2.15:1로 미달이었다.) 다크 FBBF24는 이미 밝은 노랑이라 그대로.
    static let borderActivity = NSColor.dynamic(light: 0xA16207, dark: 0xFBBF24)
    static let muted = NSColor.dynamic(light: 0x65656B, dark: 0x98989E) // 보조 텍스트 — 다크 #8A8A90은 3.82:1로 AA 탈락이었다
    static let mutedHover = NSColor.dynamic(light: 0x232326, dark: 0xE4E4E7)
    static let fg = NSColor.dynamic(light: 0x232326, dark: 0xE4E4E7)
    // 목록 선택·hover 채움 — **중립이다. 브랜드색을 쓰지 않는다**(macOS 규약: 색은 상태에만).
    //
    // **`btnActive`는 Bonsplit 탭바의 면이기도 하다**(`BonsplitChrome.colors.tabBar`) — 팔레트 수술이
    // 값을 고를 땐 없던 역할이다. 활성 탭(`bg`)이 면으로 떠오르려면 그 아래 바가 눌려 있어야 하는데,
    // 다크에서 3C3C41은 bg 대비 **1.57:1**로 c713cd5가 측정해 잡은 목표(1.9:1)를 절반쯤 되돌린다.
    // 47474C는 1.86:1 — 지표를 지키면서도 r≈g의 무채라 zinc 원칙과 충돌하지 않는다. 그래서 되살린다.
    // (`panel`을 올린 만큼 hover도 한 칸 올려 panel→hover→active 사다리를 유지한다: L* 17.7→22.3→30.3)
    static let btnHover = NSColor.dynamic(light: 0xE6E6E9, dark: 0x35353A)
    static let btnActive = NSColor.dynamic(light: 0xD6D6D9, dark: 0x47474C)

    /// 포커스 없는 칸에 덮는 베일 — **"지금 입력이 어디로 가는가"를 밝기로 말한다**(테두리 대신).
    ///
    /// 테두리는 상시 켜지면 강조를 잃는다. 같은 테두리 채널을 에이전트 알림(주황)이 쓰는데,
    /// 청록 테두리가 늘 깔려 있으면 정작 나를 부르는 주황이 그 위에서 경쟁해야 한다.
    /// 밝기로 말하면 테두리가 비고, **테두리가 뜨면 그건 진짜 알림이다**.
    ///
    /// **약하게 잡는다** — 칸을 나란히 놓고 두 터미널을 대조하는 게 이 앱의 일상이다.
    /// 안 보이는 칸을 만들면 분할의 의미가 없다. 알아볼 수 있을 만큼만 눌러 둔다.
    ///
    /// **알파는 두 모드의 *결과 밝기차*(ΔL\*)를 맞춰서 고른다 — 같은 알파가 아니라.**
    /// 검정을 곱하면 절대 변화량이 바탕 밝기에 비례하므로, 어두운 바탕에선 같은 알파가 훨씬 덜 보인다.
    /// 다크 12%는 `1B1B1D`를 `18181A`로 만들 뿐이라 **ΔL\* 1.52 · 대비 1.03:1** — 프롬프트만 있는 빈 칸에선
    /// 사실상 아무 말도 안 한다(눈에 띄는 건 글자뿐이었다). 22%면 `151517` = **ΔL\* 3.0**으로
    /// 라이트 3%(ΔL\* 2.77)와 같은 무게가 되고, 비포커스 칸의 터미널 글자는 여전히 **8.6:1**(AAA 7:1 통과)이다.
    static let paneVeil = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: 0, alpha: isDark ? 0.22 : 0.03)
    }

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
    // 실행 중(파랑 — "live"). 완료(success=초록 gitAdded)와 **한 사이드바 행에 나란히** 떠서 둘 다 초록이면
    // 헷갈렸다 → gitRenamed(파랑)로 분리한다. 파랑은 "구동 중/살아 있음"으로도 자연스럽다.
    static let serviceRunning = gitRenamed
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
    static let pGuide = Color(nsColor: Palette.guide)
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
    static let pGitAdded = Color(nsColor: Palette.gitAdded) // 완료·성공의 초록(서비스 실행중 파랑과 분리)
    static let pServiceRunning = Color(nsColor: Palette.serviceRunning)
    static let pServiceExited = Color(nsColor: Palette.serviceExited)
}
