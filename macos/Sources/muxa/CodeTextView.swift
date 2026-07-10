import AppKit
import SwiftUI

/// 코드 뷰어 표시 — 공유 ShikiHighlighter에서 토큰(색)을 받아 네이티브 NSTextView에 attributed로 그린다.
/// WKWebView 표시(파일마다 web 프로세스 스폰)를 없애 파일 열기가 즉각적. 줄바꿈 없음·가로 스크롤 + 줄번호. 읽기 전용.
struct CodeTextView: NSViewRepresentable {
    let code: String
    let language: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.bg
        scroll.borderType = .noBorder

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = Palette.bg
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = false
        // 줄바꿈 안 함 → 가로 스크롤(maxSize 필수, 없으면 본문 clip).
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        let ruler = LineNumberRuler(scrollView: scroll, textView: tv)
        scroll.verticalRulerView = ruler

        context.coordinator.textView = tv
        context.coordinator.ruler = ruler
        context.coordinator.render(code: code, language: language)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.render(code: code, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        private var lastKey = ""

        func render(code: String, language: String?) {
            let key = "\(language ?? "")|\(code.count)|\(code.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            Task { @MainActor in
                let tokens = await ShikiHighlighter.shared.tokens(code: code, language: language, dark: dark)
                guard let tv = self.textView else { return }
                tv.textStorage?.setAttributedString(Self.build(tokens: tokens))
                tv.backgroundColor = Palette.bg
                self.ruler?.needsDisplay = true
            }
        }

        static func build(tokens: [[[String]]]) -> NSAttributedString {
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.fg]
            let result = NSMutableAttributedString()
            for (i, line) in tokens.enumerated() {
                for token in line where token.count >= 2 {
                    var attrs = base
                    if let color = NSColor(hexString: token[1]) { attrs[.foregroundColor] = color }
                    result.append(NSAttributedString(string: token[0], attributes: attrs))
                }
                if i < tokens.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: base))
                }
            }
            return result.length == 0 ? NSAttributedString(string: " ", attributes: base) : result
        }
    }
}

extension NSColor {
    /// "#rrggbb" → NSColor. 실패 시 nil.
    convenience init?(hexString: String) {
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// 코드 뷰어 줄번호 ruler — 보이는 줄만 그린다(대형 파일 성능).
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
    }

    required init(coder: NSCoder) { fatalError("unsupported") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let lm = textView.layoutManager, let container = textView.textContainer else { return }
        Palette.panel.setFill()
        rect.fill()

        let content = textView.string as NSString
        let inset = textView.textContainerInset.height
        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleRect = textView.visibleRect
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Palette.muted.withAlphaComponent(0.7),
        ]

        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if charRange.location > 0 {
            content.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                        options: [.byLines, .substringNotRequired]) { _, _, _, _ in lineNumber += 1 }
        }
        content.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let lineGlyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = lm.boundingRect(forGlyphRange: lineGlyphRange, in: container)
            let y = lineRect.minY + inset + relativePoint.y
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: self.ruleThickness - size.width - 5, y: y), withAttributes: attrs)
            lineNumber += 1
        }
    }
}
