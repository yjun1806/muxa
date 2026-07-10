import AppKit
import SwiftUI

/// unified diff 네이티브 렌더 — monospace·줄바꿈 없음·가로 스크롤. 줄 앞 문자로 색을 준다
/// (+초록/-빨강/@@ 청록/헤더 muted). SwiftUI ForEach가 가로 스크롤에서 줄을 감싸(wrap) 깨지던 문제를
/// NSTextView로 해결한다(코드 뷰어 CodeTextView와 같은 방식, 하이라이터는 불필요해 동기 렌더).
struct DiffTextView: NSViewRepresentable {
    let lines: [String]

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
        tv.allowsUndo = false
        // 줄바꿈 안 함 → 가로 스크롤(maxSize 필수, 없으면 본문 clip).
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        context.coordinator.textView = tv
        context.coordinator.render(lines)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.render(lines)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        private var lastCount = -1
        private var lastFirst = ""

        func render(_ lines: [String]) {
            // 같은 diff 재렌더 방지(줄 수 + 첫 줄로 판별).
            let key = lines.first ?? ""
            guard lines.count != lastCount || key != lastFirst else { return }
            lastCount = lines.count
            lastFirst = key
            textView?.textStorage?.setAttributedString(Self.build(lines))
        }

        static func build(_ lines: [String]) -> NSAttributedString {
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let result = NSMutableAttributedString()
            for (i, line) in lines.enumerated() {
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg(line)]
                if let bg = bg(line) { attrs[.backgroundColor] = bg }
                result.append(NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs))
                if i < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                }
            }
            return result
        }

        private static func fg(_ line: String) -> NSColor {
            if line.hasPrefix("+++") || line.hasPrefix("---") { return Palette.muted }
            switch line.first {
            case "+": return .systemGreen
            case "-": return .systemRed
            case "@": return .systemTeal
            case "d", "i", "n": return Palette.muted // diff/index/new file 헤더
            default: return Palette.fg
            }
        }

        private static func bg(_ line: String) -> NSColor? {
            if line.hasPrefix("+++") || line.hasPrefix("---") { return nil }
            switch line.first {
            case "+": return NSColor.systemGreen.withAlphaComponent(0.12)
            case "-": return NSColor.systemRed.withAlphaComponent(0.12)
            default: return nil
            }
        }
    }
}
