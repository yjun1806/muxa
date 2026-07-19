import AppKit

/// 문서 diff 뷰어에 넘길 색 payload — **Palette가 단일 출처**다.
///
/// 기존 뷰어들(`CodeHTML`·mdviewer `shell.html`)은 색을 HTML 쪽에 하드코딩해 두어 팔레트가
/// 버밀리언 리브랜드로 옮겨갈 때 옛 zinc 값이 그대로 남았다. 신규 뷰어는 그 드리프트를
/// 원천 차단한다 — CSS엔 변수 이름만 있고 값은 전부 여기서 간다.
enum DocDiffTheme {

    /// CSS 변수 이름 → hex. `paint.js`가 `--<key>`로 심는다.
    static func payload(dark: Bool) -> [String: String] {
        let p: (NSColor) -> String = { hex($0, dark: dark) }
        return [
            // 본문 조판(md-body.css가 쓰는 이름 — 문서 뷰어와 같은 어휘)
            "bg": p(Palette.bg),
            "fg": p(Palette.fg),
            "muted": p(Palette.muted),
            "border": p(Palette.border),
            "panel": p(Palette.panel),
            "link": p(Palette.brand),
            // 변경 표시 — git 기능색을 그대로 쓴다(의미 고정)
            "d-add": p(Palette.gitAdded),
            "d-del": p(Palette.gitDeleted),
            "d-mod": p(Palette.gitModified),
            "d-mov": p(Palette.gitRenamed),
            // 배경 틴트 — 면이라 옅게. 기존 diff 뷰어의 틴트 문법(14%)과 같은 세기.
            "d-add-bg": tint(Palette.gitAdded, dark: dark),
            "d-del-bg": tint(Palette.gitDeleted, dark: dark),
            "d-mod-bg": tint(Palette.gitModified, dark: dark)
        ]
    }

    /// 동적 `NSColor`를 해당 모드로 해석해 hex로. (뷰어는 WebView라 동적 색이 자동 전환되지 않는다.)
    private static func hex(_ color: NSColor, dark: Bool) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var resolved = color
        appearance?.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
        let c = resolved.usingColorSpace(.sRGB) ?? resolved
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    /// 틴트 — 알파를 쓰지 않고 배경에 섞어 굽는다.
    /// (WebView 안에서 알파를 겹치면 중첩 하이라이트가 진해져 "얼마나 바뀐 건지"를 왜곡한다.)
    private static func tint(_ color: NSColor, dark: Bool) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var fg = color, bg = Palette.bg
        appearance?.performAsCurrentDrawingAppearance {
            fg = color.usingColorSpace(.sRGB) ?? color
            bg = Palette.bg.usingColorSpace(.sRGB) ?? Palette.bg
        }
        let f = fg.usingColorSpace(.sRGB) ?? fg
        let b = bg.usingColorSpace(.sRGB) ?? bg
        let a: CGFloat = dark ? 0.22 : 0.16 // 다크는 같은 알파로 덜 보인다(베일과 같은 원리)
        func mix(_ x: CGFloat, _ y: CGFloat) -> Int { Int(round((x * a + y * (1 - a)) * 255)) }
        return String(format: "#%02X%02X%02X",
                      mix(f.redComponent, b.redComponent),
                      mix(f.greenComponent, b.greenComponent),
                      mix(f.blueComponent, b.blueComponent))
    }
}
