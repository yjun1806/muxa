import Foundation

/// 코드/diff를 WKWebView에 실을 정적 HTML로 변환하는 순수 함수 모음.
/// 표시를 NSTextView가 아닌 WKWebView로 하는 이유: Bonsplit keepAllAlive(ZStack+opacity)에서
/// NSTextView 본문이 합성되지 않는(줄번호만 보이는) 문제가 있어, md 뷰어와 같은 WKWebView로 통일한다.
/// 하이라이팅 자체는 Shiki(오프스크린)가 만든 토큰 색을 그대로 인라인 span에 박는다(뷰마다 shiki 재로드 없음).
enum CodeHTML {
    /// 라이트/다크 팔레트 — Palette.swift와 값을 맞춘다(HTML은 NSColor 동적색을 못 써 hex 고정).
    private struct Theme {
        let bg, fg, muted, gutter: String
        let addFg, addBg, delFg, delBg, hunk: String
        static func of(dark: Bool) -> Theme {
            dark
            ? Theme(bg: "#1b1b1d", fg: "#e4e4e7", muted: "#8a8a90", gutter: "#252528",
                    addFg: "#3fb950", addBg: "rgba(63,185,80,.14)", delFg: "#f85149", delBg: "rgba(248,81,73,.14)", hunk: "#2dd4bf")
            : Theme(bg: "#ffffff", fg: "#1f2937", muted: "#6b7280", gutter: "#f7f8fa",
                    addFg: "#1a7f37", addBg: "rgba(26,127,55,.12)", delFg: "#cf222e", delBg: "rgba(207,34,46,.12)", hunk: "#0969da")
        }
    }

    /// HTML 특수문자 이스케이프.
    private static func esc(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            default: r.append(c)
            }
        }
        return r
    }

    private static func page(_ body: String, theme t: Theme) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:\(t.bg);color:\(t.fg);}
        .wrap{font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;padding:8px 0;}
        table.code{border-collapse:collapse;width:max-content;min-width:100%;}
        table.code td{padding:0;vertical-align:top;}
        td.ln{width:1%;white-space:nowrap;text-align:right;padding:0 18px 0 16px;color:\(t.muted);
              user-select:none;position:sticky;left:0;background:\(t.bg);border-right:1px solid \(t.gutter);}
        td.src{white-space:pre;padding:0 16px 0 44px;}
        .dl{white-space:pre;padding:0 16px;}
        .add{color:\(t.addFg);background:\(t.addBg);}
        .del{color:\(t.delFg);background:\(t.delBg);}
        .hunk{color:\(t.hunk);}
        .meta{color:\(t.muted);}
        </style></head><body><div class="wrap">\(body)</div></body></html>
        """
    }

    /// Shiki 토큰([[[content,color],...],...]) → 줄번호 있는 코드 표.
    static func code(tokens: [[[String]]], dark: Bool) -> String {
        let t = Theme.of(dark: dark)
        var rows = ""
        for (i, line) in tokens.enumerated() {
            var src = ""
            for tok in line where tok.count >= 1 {
                let content = esc(tok[0])
                if tok.count >= 2, !tok[1].isEmpty {
                    src += "<span style=\"color:\(tok[1])\">\(content)</span>"
                } else {
                    src += content
                }
            }
            rows += "<tr><td class=\"ln\">\(i + 1)</td><td class=\"src\">\(src.isEmpty ? " " : src)</td></tr>"
        }
        return page("<table class=\"code\">\(rows)</table>", theme: t)
    }

    /// unified diff 줄들 → 색칠된 diff 뷰(줄 앞 문자로 add/del/hunk/meta 구분).
    static func diff(lines: [String], dark: Bool) -> String {
        let t = Theme.of(dark: dark)
        var body = ""
        for line in lines {
            let cls: String
            if line.hasPrefix("+++") || line.hasPrefix("---") { cls = "meta" }
            else if line.hasPrefix("+") { cls = "add" }
            else if line.hasPrefix("-") { cls = "del" }
            else if line.hasPrefix("@") { cls = "hunk" }
            else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("new ") || line.hasPrefix("deleted ") { cls = "meta" }
            else { cls = "" }
            body += "<div class=\"dl \(cls)\">\(esc(line.isEmpty ? " " : line))</div>"
        }
        return page(body, theme: t)
    }
}
