import AppKit
import Testing

@testable import muxa

/// `Palette`(동적 NSColor) → Bonsplit(hex 문자열) 변환.
///
/// 이 변환은 **틀려도 조용하다** — 앱은 그냥 이상한 색으로 뜨고, 다크 모드에서만 틀릴 수도 있다.
/// 눈으로 잡으려면 두 외관을 다 열어봐야 하므로 여기서 못 박는다.
@Suite("BonsplitChrome — 팔레트 → hex")
struct BonsplitChromeTests {
    @Test("동적 색이 라이트/다크 각각의 값으로 해석된다")
    func resolvesBothAppearances() {
        // 스코프 밖에서 성분을 읽으면 조용히 라이트 값이 나온다 — 그 함정에 빠지면 이 테스트가 깨진다.
        #expect(Palette.bg.bonsplitHexPair.light == "#FCFBFAFF")
        #expect(Palette.bg.bonsplitHexPair.dark == "#1C1A18FF")

        #expect(Palette.btnActive.bonsplitHexPair.light == "#DFDAD3FF")
        #expect(Palette.btnActive.bonsplitHexPair.dark == "#454037FF")
    }

    /// 강조는 **버밀리언**(UI accent)이지 아이콘의 키 컬러가 아니다 — 아이콘 색(`Palette.Brand.key`)은
    /// Dock 전용으로 격리돼 UI accent보다 진하다. UI는 accent 값만 쓴다. 이 테스트는 그 격리가 다시 새는 걸 막는다.
    @Test("브랜드 강조는 라이트에서 진하고 다크에서 밝다 — 단 아이콘 색이 UI로 새지 않는다")
    func brandFlipsWithAppearance() {
        let brand = Palette.brand.bonsplitHexPair
        #expect(brand.light == "#C13A1BFF")
        #expect(brand.dark == "#EE6B44FF")
        #expect(brand.dark != "#\(String(format: "%06X", Palette.Brand.key))FF") // 아이콘 전용 색이 UI로 새지 않는다
    }

    /// 알파를 6자리로 자르면 반투명 색이 **완전 불투명**해진다.
    /// 베일(3%)이 불투명 검정이 되면 그 칸이 통째로 까맣게 덮인다 — 조용한 참사다.
    @Test("알파가 보존된다")
    func preservesAlpha() {
        let veil = Palette.paneVeil.bonsplitHexPair
        #expect(veil.light.count == 9) // "#RRGGBBAA"
        #expect(veil.light.hasSuffix("08")) // 3% ≈ 8/255
        #expect(veil.dark.hasSuffix("38")) // 22% ≈ 56/255 — 다크는 곱연산 손해가 커서 알파를 더 준다(ΔL*를 맞춘다)
        #expect(!veil.dark.hasSuffix("FF")) // 불투명해지면 그 칸이 통째로 까맣게 덮인다
    }

    /// 탭바(크롬)와 활성 탭(콘텐츠)은 **다른 면**이어야 한다 — 같으면 활성 탭이 시각적으로 사라진다.
    /// (시스템 색을 쓰던 시절 `windowBackground == controlBackground`라 대비가 1.00:1이었다.)
    @Test("탭바와 활성 탭이 같은 색이 아니다")
    func tabBarContrastsWithActiveTab() {
        let bar = BonsplitChrome.colors.tabBar
        let tab = BonsplitChrome.colors.activeTab
        #expect(bar?.light != tab?.light)
        #expect(bar?.dark != tab?.dark)
    }

    /// 분할 버튼 레인의 backdrop은 **투명을 명시**해야 한다.
    /// 비워두면 Bonsplit이 탭바 색에서 파생해 불투명하게 칠하고, 레인 아래로 흘러가야 할 탭이 뚝 잘린다.
    @Test("분할 버튼 레인 backdrop은 투명이다")
    func splitButtonBackdropIsTransparent() {
        let backdrop = BonsplitChrome.colors.splitButtonBackdrop
        #expect(backdrop?.light == "#00000000")
        #expect(backdrop?.dark == "#00000000")
    }
}
