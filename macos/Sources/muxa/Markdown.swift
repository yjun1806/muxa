import Foundation

/// Markdown 블록 모델 — 라인 기반 파서의 출력(순수 데이터). 뷰어(MarkdownView)가 렌더한다.
/// 네이티브 1차 범위: heading/list/codefence/blockquote/rule/문단. 표·mermaid는 후속(WKWebView).
enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, ordered: Bool)
    case code(String)        // 코드펜스 내용(언어 무시)
    case quote(String)
    case rule

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l):\(t)"
        case .paragraph(let t): return "p:\(t)"
        case .bullet(let t, let o): return "b\(o):\(t)"
        case .code(let t): return "c:\(t.prefix(40))"
        case .quote(let t): return "q:\(t)"
        case .rule: return "hr:\(UUID().uuidString)"
        }
    }
}

/// 최소 Markdown 블록 파서 — 순수 함수(부작용 없음). 인라인 강조는 렌더가 AttributedString으로 처리.
enum Markdown {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine

            // 코드펜스 토글
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flushParagraph(); continue }

            // 수평선
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(); blocks.append(.rule); continue
            }
            // 헤딩
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                if hashes >= 1 && hashes <= 6 {
                    flushParagraph()
                    let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: text))
                    continue
                }
            }
            // 인용
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
                continue
            }
            // 순서 없는 리스트
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2)), ordered: false))
                continue
            }
            // 순서 있는 리스트 (1. text)
            if let dot = trimmed.firstIndex(of: "."),
               dot > trimmed.startIndex, // 점 앞에 숫자가 최소 1개(빈 범위 allSatisfy 공허참 방지)
               trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                flushParagraph()
                let text = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                blocks.append(.bullet(text: text, ordered: true))
                continue
            }

            paragraph.append(trimmed)
        }
        if inCode { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
