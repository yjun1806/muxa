import AppKit
import Bonsplit

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
    /// `panel`은 `bg`와 너무 가까워 다크에서 대비가 1.15:1까지 떨어졌다(회색 위의 회색).
    /// 팔레트에서 가장 진한 중립인 `btnActive`로 내리면 1.92:1이 된다.
    ///
    /// **활성 탭이 `bg`인 이유** — 탭 바로 아래 터미널 배경이 같은 `bg`다. 두 면이 같은 색이면
    /// 활성 탭이 콘텐츠의 앞머리로 읽힌다(Safari·Xcode 문법). 상단 `ProjectTabBar`도 같은 규칙이라
    /// 앱 안에서 "활성 탭" 문법이 하나가 된다. Bonsplit 기본값은 이걸 못 만든다 —
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

    /// 탭 카드의 위 두 모서리. 아래는 각져야 면이 콘텐츠로 흘러내린다.
    static let tabCornerRadius: CGFloat = Radius.md

    /// 카드가 탭바 상단에서 떨어지는 거리. 이게 0이면 카드가 바를 꽉 채워
    /// **모서리 곡선이 바 경계에 잘려** 라운드가 아니라 잘린 것처럼 보인다.
    static let tabTopInset: CGFloat = 3

    /// 지시선은 탭 **아래쪽**에 긋는다. 위에 그으면 탭 카드 위로 선이 하나 더 얹혀 시끄럽고,
    /// 아래는 탭과 콘텐츠가 만나는 자리라 "이 탭이 아래 화면"이라는 말과 같은 방향이다.
    static let activeIndicatorAtBottom = true

    /// 포커스된 칸의 선택 탭 — teal, 2pt.
    static let activeIndicatorHeight: CGFloat = 2

    /// 포커스 없는 칸의 선택 탭 — 회색, 얇게. "이 칸에선 이 탭"은 말하되
    /// "여기로 입력이 간다"는 말하지 않는다. 굵기 차이는 색을 지워도 남는 신호다.
    static let inactiveIndicatorHeight: CGFloat = 1
}
