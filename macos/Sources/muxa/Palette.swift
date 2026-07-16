import AppKit
import SwiftUI

/// 앱 크롬 색 팔레트. 시스템 외관(라이트/다크)에 따라 값이 바뀌는 동적 NSColor다.
/// 색은 여기 한 곳에만 두고, AppKit/SwiftUI 어디서든 이 값을 참조한다(하드코딩 금지).
///
/// **설계 원칙 — 완전 무채 웜 그레이 크롬, 색은 신호다 (색상 피로도 최적화).**
/// 8시간 응시하는 터미널에서 채도는 곧 피로다(잔상 = 면적×시간×채도). 게다가 ANSI 콘텐츠가 이미
/// 화면의 유채색 예산을 다 쓴다. 그래서 화면의 색을 셋으로 나눈다:
/// ① **배경·크롬 전부 = 완전 무채 웜 그레이**(채도 ≈0 → 피로 ≈0, 웜이라 차갑지 않다) —
///    zinc(청보라 H≈286)의 차가움을 걷어내고 웜(H≈40 근처, 채도 최소)으로 돌렸다.
/// ② **상태 점 = 기능색**(`work` 틸·`borderActivity` 앰버·git·서비스) — 작은 점만, 조용한 배경 위에서 pop.
/// ③ **`brand` = 선셋 버밀리언(#C13A1B/#EE6B44) — 강조 지점에만 조금씩**(포커스·선택 지시선·CTA·링크·아이콘).
///    면(fill)이 아니라 선·글리프로만, 크롬 픽셀의 1% 미만. 그래서 가장 뜨거운 색인데도 눈이 안 지친다.
///
/// **`brand`(버밀리언)와 `work`(틸)는 별개다.** 예전엔 `brand`(딥틸)가 UI 강조와 "작업 중" 상태를
/// 겸했는데, 버밀리언 리브랜드에서 갈랐다 — 틸은 `work`로 분리해 순수 상태색이 되고(재학습 0),
/// 버밀리언은 UI 강조 전용이 된다. `StatusStyle.active`는 이제 `work`를 가리킨다.
///
/// **포커스는 색이 아니라 밝기로 말한다**(D20). 칸 포커스 링은 없애고 `paneVeil`(무채)로 대체했다.
/// 테두리 채널은 에이전트 알림(`borderActivity`)에만 내준다.
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
        /// 아이콘 심볼(낙서 X) 색 = 선셋 버밀리언(고채도). 아이콘은 Dock 격리라 UI accent(`brand`)보다 진해도 된다.
        static let key: UInt32 = 0xE24A20
        /// 아이콘 배경 squircle 그라디언트 양 끝 — 다크 그래파이트 명(위)·암(아래).
        static let gradTop: UInt32 = 0x2C2825
        static let gradBottom: UInt32 = 0x151312
    }

    // MARK: 강조 semantic 토큰 (선셋 버밀리언 — 강조 지점에만 조금씩)
    //
    /// 강조 텍스트·링크·포커스 지시선·1급 CTA·아이콘. 키컬러 #C13A1B(라이트)는 흰 배경 대비 ≈4.7:1,
    /// 다크는 어둠 위에서 읽히게 한 단 밝힌 #EE6B44(≈5.5:1). **면이 아니라 선·글리프로만** 써서
    /// 크롬 픽셀의 1% 미만으로 묶는다 — 그래야 가장 뜨거운 색인데도 잔상·피로가 안 생긴다.
    static let brand = NSColor.dynamic(light: 0xC13A1B, dark: 0xEE6B44)
    // MARK: 에이전트 상태색 — 브랜드·git과 별개, 저채도 조화 세트 (작업중 인디고 · 대기 로즈 · 완료 세이지)
    //
    // 상태는 색 + **모양 + 움직임** 3채널로 말한다(색맹 안전): 작업중=스피너 회전, 대기=펄스, 완료=체크, 유휴=무표시.
    // 색은 서로 확실히 갈리되(작업 쿨 인디고 ↔ 완료 세이지, 대기 로즈는 앰버 아님) 브랜드 버밀리언과 같은 저채도 톤.
    //
    /// 상태색 hex(SSOT) — 사이드바 마크·칸 테두리·**탭 status 마크**가 같은 값을 쓰게 한다.
    /// 아래 NSColor와 `TabStatusMapping`이 전부 여기서 파생한다(값 하나만 고치면 셋 다 따라온다 — 드리프트 방지).
    enum StatusHex {
        static let work = (light: "3A5FD0", dark: "7C9BF0")     // 인디고
        static let waiting = (light: "A8506A", dark: "D68DA3")  // 더스티 로즈
        static let done = (light: "4E8A52", dark: "86C486")     // 세이지 그린
    }

    /// **작업 중(active) — 인디고.** `StatusStyle.active`. 완료 세이지·git 초록과 확실히 갈리는 쿨톤("처리중").
    static let work = NSColor.dynamic(lightHex: StatusHex.work.light, darkHex: StatusHex.work.dark)
    /// **입력 대기(attention) — 더스티 로즈.** 앰버(`borderActivity`)와 분리한 상태 전용색(경보 아님 — 사람을 기다린다).
    static let waiting = NSColor.dynamic(lightHex: StatusHex.waiting.light, darkHex: StatusHex.waiting.dark)
    /// **완료(success) — 세이지 그린.** git 초록(`gitAdded`)과 분리 — "끝났다"의 차분한 초록.
    static let done = NSColor.dynamic(lightHex: StatusHex.done.light, darkHex: StatusHex.done.dark)
    /// 옅은 강조 배경 틴트(버밀리언). **목록 선택에는 쓰지 않는다**(선택은 중립 `btnActive`가 macOS 규약).
    /// 팝오버·안내 배너 같은 데만. 웜 크롬에 묻히지 않게 반 톤 벌렸다.
    static let brandSubtle = NSColor.dynamic(light: 0xF6E8E3, dark: 0x3A2018)
    /// 강조 hover — 한 단계 진하게.
    static let brandHover = NSColor.dynamic(light: 0xA82E12, dark: 0xF3855F)
    /// **`brand` 채움 위에 얹는 전경**(1급 CTA 글자). 라이트는 어두운 버밀리언 위 흰 글자,
    /// 다크는 밝은 버밀리언 위 딥 브라운(대비 확보). 양 모드 AA 통과.
    static let onBrand = NSColor.dynamic(light: 0xFFFFFF, dark: 0x3A1305)

    // MARK: - 중립(완전 무채 웜 그레이)
    //
    // 채도는 거의 0(피로 ≈0)이되 **웜 쪽**으로 — zinc(청보라 H≈286)의 차가움을 걷어내고 웜(H≈40 근처)으로
    // 돌렸다. 명도 계단(ΔL* 다크 7.8·라이트 5.5, panel→hover→active 사다리)은 검증된 값을 온도만 바꿔 계승한다.
    // 다크 bg는 순검정을 피해 L*≈11(halation·명순응 왕복 완화), 라이트 bg는 순백 대신 웜 오프화이트.
    static let bg = NSColor.dynamic(light: 0xFCFBFA, dark: 0x1C1A18) // 콘텐츠·패인 배경
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
    static let panel = NSColor.dynamic(light: 0xF0EEEB, dark: 0x2B2926) // 상단바·사이드바·패인 헤더(한 덩어리 웜 그레이)
    // 카드 경계이자 **카드 안의 패널↔터미널 분할선**. 고도가 못 닿는 그 선이 유일한 신호라 함께 올렸다
    // (다크 34343A→3E3E44: bg 대비 1.39→1.62, panel 대비 1.14→1.33).
    static let border = NSColor.dynamic(light: 0xDEDAD5, dark: 0x423F3A)
    // 사이드바 2단 트리의 **세로 가이드선** — 프로젝트를 그 워크스페이스 아래로 묶어 소속을 그린다.
    // 1px가 panel 위에서 읽혀야 하므로 border보다 살짝 진하게 잡는다(다크 3E3E44는 panel 대비 안 보였다 → 54545C).
    static let guide = NSColor.dynamic(light: 0xCBC6BF, dark: 0x58534C)
    // 활동·주의 환기(호박). 라이트를 B45309(적갈색)→A16207(앰버/머스터드)로 옮겼다 — 적갈색이 실패색
    // #CF222E(빨강)와 헷갈렸다(에러처럼 읽힘). A16207은 초록 채널이 살아 확실한 앰버고 흰 배경 대비 4.9:1(AA).
    // (#F59E0B는 2.15:1로 미달이었다.) 다크 FBBF24는 이미 밝은 노랑이라 그대로.
    static let borderActivity = NSColor.dynamic(light: 0xA16207, dark: 0xFBBF24)
    static let muted = NSColor.dynamic(light: 0x6B655E, dark: 0xA29C94) // 보조 텍스트 — 양 모드 AA(≈5:1)
    static let mutedHover = NSColor.dynamic(light: 0x26231F, dark: 0xE9E5E0)
    static let fg = NSColor.dynamic(light: 0x26231F, dark: 0xE9E5E0) // 웜 잉크 — 순검정/순백 회피
    // 목록 선택·hover 채움 — **중립이다. 브랜드색을 쓰지 않는다**(macOS 규약: 색은 상태에만).
    //
    // **`btnActive`는 Bonsplit 탭바의 면이기도 하다**(`BonsplitChrome.colors.tabBar`) — 팔레트 수술이
    // 값을 고를 땐 없던 역할이다. 활성 탭(`bg`)이 면으로 떠오르려면 그 아래 바가 눌려 있어야 하는데,
    // 다크에서 3C3C41은 bg 대비 **1.57:1**로 c713cd5가 측정해 잡은 목표(1.9:1)를 절반쯤 되돌린다.
    // 47474C는 1.86:1 — 지표를 지키면서도 r≈g의 무채라 zinc 원칙과 충돌하지 않는다. 그래서 되살린다.
    // (`panel`을 올린 만큼 hover도 한 칸 올려 panel→hover→active 사다리를 유지한다: L* 17.7→22.3→30.3)
    static let btnHover = NSColor.dynamic(light: 0xE9E5E0, dark: 0x39352F)
    static let btnActive = NSColor.dynamic(light: 0xDFDAD3, dark: 0x454037)

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

    /// hex 문자열("RRGGBB") 버전 — 상태색 hex SSOT(`StatusHex`)가 NSColor로 흐르는 통로.
    static func dynamic(lightHex: String, darkHex: String) -> NSColor {
        dynamic(light: UInt32(lightHex, radix: 16) ?? 0, dark: UInt32(darkHex, radix: 16) ?? 0)
    }
}

/// SwiftUI에서 쓰는 팔레트 별칭 — NSColor 단일 진실을 그대로 감싼다(동적 색이라 라이트/다크 자동 반응).
extension Color {
    static let pBg = Color(nsColor: Palette.bg)
    static let pPanel = Color(nsColor: Palette.panel)
    static let pBorder = Color(nsColor: Palette.border)
    static let pGuide = Color(nsColor: Palette.guide)
    static let pBrand = Color(nsColor: Palette.brand)
    static let pWork = Color(nsColor: Palette.work) // 작업 중(active) — 인디고
    static let pWaiting = Color(nsColor: Palette.waiting) // 입력 대기(attention) — 로즈
    static let pDone = Color(nsColor: Palette.done) // 완료(success) — 세이지
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
