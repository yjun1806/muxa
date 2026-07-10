import AppKit
import SwiftUI

/// 코드 뷰어 본체 — 하이라이트한 NSAttributedString을 NSTextView에 표시(줄바꿈 없음·가로 스크롤).
/// 줄번호는 NSRulerView로 그린다(텍스트에 섞지 않아 선택·복사에 안 낀다). 읽기 전용.
struct CodeTextView: NSViewRepresentable {
    let code: String
    let language: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = Palette.bg
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        // 줄바꿈 안 함 → 가로 스크롤
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.bg

        // 줄번호 ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        let ruler = LineNumberRuler(scrollView: scroll, textView: textView)
        scroll.verticalRulerView = ruler

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.apply(code: code, language: language)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(code: code, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        private var lastKey = ""

        func apply(code: String, language: String?) {
            let key = "\(language ?? "")|\(code.count)|\(code.prefix(80))"
            guard key != lastKey else { return }
            lastKey = key
            let dark = GhosttyRuntime.systemIsDark
            Task.detached {
                let attr = CodeHighlighter.shared.highlight(code, language: language, dark: dark)
                await MainActor.run {
                    guard let tv = self.textView else { return }
                    tv.textStorage?.setAttributedString(attr)
                    tv.backgroundColor = Palette.bg
                    tv.sizeToFit()
                    self.ruler?.needsDisplay = true
                }
            }
        }
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
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        // 배경
        Palette.panel.setFill()
        rect.fill()
        NSColor.clear.set()

        let content = textView.string as NSString
        let inset = textView.textContainerInset.height
        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleRect = textView.visibleRect

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Palette.muted.withAlphaComponent(0.7),
        ]

        // 보이는 글리프 범위 → 문자 범위
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // 시작 줄 번호(문서 처음부터 charRange.location까지의 개행 수 + 1)
        var lineNumber = 1
        if charRange.location > 0 {
            content.enumerateSubstrings(
                in: NSRange(location: 0, length: charRange.location),
                options: [.byLines, .substringNotRequired]
            ) { _, _, _, _ in lineNumber += 1 }
        }

        // 보이는 각 줄에 번호
        content.enumerateSubstrings(
            in: charRange,
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: container)
            let y = lineRect.minY + inset + relativePoint.y
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: self.ruleThickness - size.width - 5, y: y), withAttributes: attrs)
            lineNumber += 1
        }
    }
}
