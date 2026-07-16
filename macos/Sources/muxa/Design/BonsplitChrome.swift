import AppKit
import Bonsplit
import SwiftUI

/// Bonsplit 탭바에 muxa 팔레트를 입히는 어댑터.
///
/// Bonsplit은 색을 **hex 문자열**로 받고 muxa `Palette`는 **동적 NSColor**다. 그 사이를 여기서만 잇는다 —
/// hex를 손으로 옮겨 적으면 팔레트가 색의 단일 출처이길 그만두므로, 동적 색을 두 외관으로 각각
/// resolve해 쌍으로 넘긴다. Bonsplit은 그 쌍으로 다시 동적 NSColor를 만들므로
/// **라이트/다크 전환 시 재주입이 필요 없다**.
extension NSColor {
    /// 동적 색 → Bonsplit이 받는 라이트/다크 hex 쌍.
    var bonsplitHexPair: BonsplitConfiguration.Appearance.DynamicHex {
        .init(light: bonsplitHex(in: .aqua), dark: bonsplitHex(in: .darkAqua))
    }

    /// 이 색을 주어진 외관에서 해석해 `#RRGGBBAA`로. **알파를 포함한다** —
    /// 6자리로 자르면 반투명 색(`Palette.paneVeil` 같은)이 소리 없이 불투명해진다.
    ///
    /// 동적 색(`NSColor.dynamic`)은 **그리기 외관 스코프 안에서만** 제 값으로 해석된다.
    /// 스코프 밖에서 성분을 읽으면 조용히 라이트 값이 나온다.
    private func bonsplitHex(in appearanceName: NSAppearance.Name) -> String {
        var rgba: (r: Int, g: Int, b: Int, a: Int)?
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            // sRGB로 못 바꾸는 색(패턴·카탈로그 등)에서 성분을 읽으면 ObjC 예외가 나고
            // Swift가 못 잡아 앱이 죽는다. 실패는 값으로 만든다.
            guard let c = self.usingColorSpace(.sRGB) else { return }
            rgba = (Int((c.redComponent * 255).rounded()),
                    Int((c.greenComponent * 255).rounded()),
                    Int((c.blueComponent * 255).rounded()),
                    Int((c.alphaComponent * 255).rounded()))
        }
        guard let rgba else {
            assertionFailure("Palette 색을 sRGB로 해석하지 못했다 — 팔레트에 패턴/카탈로그 색이 들어왔나?")
            return "#00000000" // 투명 — 눈에 띄지 않게 실패한다(틀린 색을 그리느니).
        }
        return String(format: "#%02X%02X%02X%02X", rgba.r, rgba.g, rgba.b, rgba.a)
    }
}

enum BonsplitChrome {
    /// 탭바·칸의 색 = muxa 팔레트. 값은 전부 `Palette`에서 오고 여기서 새로 만들지 않는다.
    ///
    /// **탭바가 `btnActive`(진한 회색)인 이유** — 활성 탭(`bg`)을 띄우려면 그 아래 면이 눌려 있어야 한다.
    /// `panel`은 `bg`와 가까워 다크에서 대비가 1.22:1뿐이다(회색 위의 회색).
    /// 팔레트에서 가장 진한 중립인 `btnActive`로 내리면 1.86:1이 된다.
    /// (그래서 `Palette.btnActive`의 다크 값은 이 대비를 지키는 선에 묶여 있다 — 거길 낮추면 여기가 뭉갠다.)
    ///
    /// **활성 탭이 `bg`인 이유** — 탭 바로 아래 터미널 배경이 같은 `bg`다. 두 면이 같은 색이면
    /// 활성 탭이 콘텐츠의 앞머리로 읽힌다(Safari·Xcode 문법). Bonsplit 기본값은 이걸 못 만든다 —
    /// 탭바 색에서 **멀어지는 쪽으로만** 파생하므로 방향이 정반대다.
    ///
    /// **활성 탭을 윤곽선으로 감싸지 않는다** — 탭을 두르는 사각형은 크롬을 시끄럽게 만든다.
    /// 면(`bg`)이 이미 "이 탭이 아래 화면"이라고 말하고, 그 위에 **하단 선 하나**만 얹는다
    /// (`activeIndicatorAtBottom`). 포커스된 칸에서만 그 선이 brand(teal)다.
    ///
    /// **`splitButtonBackdrop`이 투명인 이유** — 이걸 비워두면 Bonsplit이 분할 버튼 레인의 backdrop을
    /// **탭바 색에서 파생**해 불투명하게 칠하고, 그러면 레인 아래로 흐릿하게 흘러가야 할 탭이
    /// 뚝 잘린 것처럼 보인다. 투명을 **명시**하면 레인 면만 안 칠하고 페이드는 그대로 살아남는다
    /// (두 동작은 독립 변수다).
    static var colors: BonsplitConfiguration.Appearance.ChromeColors {
        .init(
            tabBar: Palette.btnActive.bonsplitHexPair,
            splitButtonBackdrop: .init("#00000000"),
            paneBackground: Palette.bg.bonsplitHexPair,
            border: Palette.border.bonsplitHexPair,
            activeTab: Palette.bg.bonsplitHexPair,
            hoverTab: Palette.btnHover.bonsplitHexPair,
            activeText: Palette.fg.bonsplitHexPair,
            inactiveText: Palette.muted.bonsplitHexPair,
            activeIndicator: Palette.brand.bonsplitHexPair,
            inactiveIndicator: Palette.muted.bonsplitHexPair,
            activeIconFocused: Palette.brand.bonsplitHexPair
        )
    }

    /// 탭·활성 탭 스타일 knob을 **설정(`TabStyleSettings`)에서** appearance로 옮긴다. 칸 배치·색 팔레트
    /// (`colors`)·탭바 높이 등은 건드리지 않고, 스타일 관련 knob과 활성 탭 면 색만 덮어쓴다.
    ///
    /// fork가 속성만 제공하고 값은 muxa가 정한다 — 그 "값"의 단일 출처가 이제 `TabStyleSettings`다.
    /// 스타일 프리셋 → knob 매핑은 `TabStyleSettings.knobs(for:radius:thickness:)`(순수)에 있다.
    /// 활성 탭 면 색: `filled`면 콘텐츠(bg)로 채워 카드처럼, 아니면 탭바 색으로 둬 면이 안 보이게(선·굵기만).
    static func applyTabStyle(_ s: TabStyleSettings, to a: inout BonsplitConfiguration.Appearance) {
        a.tabHorizontalPadding = CGFloat(s.horizontalPadding)
        let k = TabStyleSettings.knobs(for: s.activeStyle,
                                       radius: CGFloat(s.cornerRadius),
                                       thickness: CGFloat(s.indicatorThickness))
        a.tabCornerRadius = k.tabCornerRadius
        a.tabTopInset = k.tabTopInset
        a.activeIndicatorAtBottom = k.indicatorAtBottom
        a.activeIndicatorHeight = k.activeIndicatorHeight
        a.inactiveIndicatorHeight = k.inactiveIndicatorHeight
        a.activeIndicatorHorizontalInset = k.indicatorInset
        a.activeIndicatorCornerRadius = k.indicatorCornerRadius
        a.activeTabFillCornerRadius = k.fillCornerRadius
        a.activeTabFillVerticalInset = k.fillVInset
        a.activeTabFillHorizontalInset = k.fillHInset
        a.selectedTabTitleWeight = k.bold ? .semibold : .regular
        // 활성 탭 면 색은 `filled`(=스타일)에만 의존하고 슬라이더(패딩·반경·두께)와 무관하다.
        // 팔레트 hex는 런타임에 안 바뀌므로 두 값을 **한 번만** 해석해 캐시한다(슬라이더 드래그마다
        // NSAppearance 그리기 컨텍스트를 2번씩 전환하던 낭비 제거).
        a.chromeColors.activeTab = k.filled ? Self.filledActiveTab : Self.flatActiveTab
    }

    /// 활성 탭 면 색(채움/평면) — static let이라 최초 접근 시 1회만 해석된다.
    private static let filledActiveTab = Palette.bg.bonsplitHexPair       // 콘텐츠색(카드·pill·블록)
    private static let flatActiveTab = Palette.btnActive.bonsplitHexPair  // 탭바색=면 안 보임(밑줄·미니멀)
}
