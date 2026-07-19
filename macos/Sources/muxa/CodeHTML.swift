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

    /// 속성값 이스케이프(큰따옴표 포함) — data-* 속성에 줄 내용을 안전히 싣는다.
    private static func escAttr(_ s: String) -> String {
        var r = esc(s)
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        return r
    }

    private static func page(_ body: String, theme t: Theme, script: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:\(t.bg);color:\(t.fg);}
        .wrap{font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;padding:8px 0;}
        table.code{border-collapse:collapse;width:100%;table-layout:fixed;}
        /* `table-layout:fixed`는 **첫 행**에서 열 너비를 읽는다. 그런데 첫 행이 colspan 파일 헤더라
           읽을 게 없어 열을 균등 분할해버린다(줄번호 열이 화면의 1/4을 먹었다). colgroup으로 못 박는다. */
        table.code col.cln{width:64px;}
        table.code td{vertical-align:top;}
        table.code td.ln{width:1%;white-space:nowrap;text-align:right;padding:0 18px 0 16px;color:\(t.muted);
              user-select:none;position:sticky;left:0;background:\(t.bg);border-right:1px solid \(t.gutter);}
        table.code td.src{white-space:pre-wrap;overflow-wrap:anywhere;padding:0 16px 0 44px;}
        .dl{white-space:pre-wrap;overflow-wrap:anywhere;padding:0 16px;}
        /* 변경 위치 레일 — macOS 오버레이 스크롤바는 CSS로 못 칠하므로 별도 div로 띄운다. */
        #muxa-minimap{position:fixed;top:0;right:0;width:10px;height:100%;z-index:50;
              pointer-events:none;}
        #muxa-minimap i{position:absolute;right:2px;width:6px;height:3px;border-radius:2px;
              pointer-events:auto;cursor:pointer;opacity:.85;}
        #muxa-minimap i:hover{opacity:1;width:8px;right:1px;}
        #muxa-minimap i.mm-add{background:\(t.addFg);}
        #muxa-minimap i.mm-del{background:\(t.delFg);}
        #muxa-minimap i.mm-mod{background:\(t.hunk);}
        .add{color:\(t.addFg);background:\(t.addBg);}
        .del{color:\(t.delFg);background:\(t.delBg);}
        .hunk{color:\(t.hunk);}
        .meta{color:\(t.muted);}
        .hunkrow{display:flex;align-items:center;gap:10px;white-space:normal;}
        .hunktext{white-space:pre-wrap;overflow-wrap:anywhere;}
        .stagebtn{font:11px ui-monospace,SFMono-Regular,Menlo,monospace;color:\(t.addFg);
              background:\(t.addBg);border:1px solid \(t.addFg);border-radius:4px;padding:0 8px;cursor:pointer;user-select:none;}
        .stagebtn:hover{background:\(t.addFg);color:\(t.bg);}
        .discardbtn{font:11px ui-monospace,SFMono-Regular,Menlo,monospace;color:\(t.delFg);
              background:\(t.delBg);border:1px solid \(t.delFg);border-radius:4px;padding:0 8px;cursor:pointer;user-select:none;}
        .discardbtn:hover{background:\(t.delFg);color:\(t.bg);}
        html[data-busy] .stagebtn,html[data-busy] .discardbtn{opacity:.45;pointer-events:none;}
        .filehdr{position:sticky;top:0;z-index:3;background:\(t.gutter);color:\(t.fg);font-weight:600;
              padding:6px 16px;border-top:1px solid \(t.hunk);border-bottom:1px solid \(t.hunk);
              white-space:pre;overflow:hidden;text-overflow:ellipsis;}
        .dl.cmtline{position:relative;}
        .cmtbtn{position:absolute;left:1px;top:0;width:14px;height:100%;padding:0;line-height:1;
              font:12px ui-monospace,Menlo,monospace;color:\(t.hunk);background:transparent;border:0;
              cursor:pointer;opacity:0;user-select:none;}
        .dl.cmtline:hover .cmtbtn{opacity:.9;}
        .cmtcard{margin:2px 16px 6px 44px;border-left:2px solid \(t.hunk);background:\(t.gutter);
              border-radius:4px;padding:5px 10px;white-space:normal;}
        .cmtmeta{display:flex;align-items:center;gap:8px;margin-bottom:2px;}
        .cmtstatus{font-size:10px;padding:0 6px;border-radius:8px;font-weight:600;}
        .st-moved{color:\(t.hunk);background:rgba(45,212,191,.14);}
        .st-outdated{color:\(t.delFg);background:\(t.delBg);}
        .cmtbody{color:\(t.fg);font-size:12px;white-space:pre-wrap;}
        .cmtwhere{color:\(t.muted);font-size:10px;font-family:ui-monospace,Menlo,monospace;}
        .cmtdel{margin-left:auto;font-size:10px;color:\(t.muted);background:transparent;border:0;
              cursor:pointer;padding:0;user-select:none;}
        .cmtdel:hover{color:\(t.delFg);}
        .outdatedwrap{margin:8px 16px;padding:6px 10px;border:1px solid \(t.delFg);border-radius:5px;background:\(t.delBg);}
        .outdatedttl{font-size:11px;font-weight:600;color:\(t.delFg);margin-bottom:4px;}
        table.sxs{border-collapse:collapse;width:100%;table-layout:fixed;}
        table.sxs col.cln{width:52px;}
        table.sxs td{vertical-align:top;}
        table.sxs td.ln{width:1%;white-space:nowrap;text-align:right;padding:0 8px;color:\(t.muted);
              user-select:none;background:\(t.gutter);}
        table.sxs td.src{white-space:pre-wrap;overflow-wrap:anywhere;padding:0 12px 0 8px;}
        table.sxs td.midsrc{border-right:1px solid \(t.gutter);}
        table.sxs td.empty{background:\(t.gutter);}
        table.sxs td.hunkhdr{padding:2px 16px;white-space:pre-wrap;color:\(t.hunk);}
        </style></head><body><div class="wrap">\(body)</div>\(script)</body></html>
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
        return page("<table class=\"code\"><colgroup><col class=\"cln\"><col></colgroup>\(rows)</table>", theme: t)
    }

    /// 앵커된 코멘트의 배치 키 — (파일, side, 줄번호)로 현재 diff 줄과 대조한다.
    private static func placementKey(file: String, side: DiffSide, line: Int) -> String {
        "\(file)\u{1}\(side.rawValue)\u{1}\(line)"
    }

    /// 코멘트 카드 HTML(상태 배지 + 본문 + 삭제 버튼).
    private static func card(_ c: AnchoredComment, theme t: Theme) -> String {
        var badge = ""
        switch c.status {
        case .moved: badge = "<span class=\"cmtstatus st-moved\">옮김</span>"
        case .outdated: badge = "<span class=\"cmtstatus st-outdated\">오래됨</span>"
        case .anchored: badge = ""
        }
        let where_ = "<span class=\"cmtwhere\">:\(c.comment.line)</span>"
        let del = "<button class=\"cmtdel\" onclick=\"muxaDeleteComment('\(c.comment.id)')\">삭제</button>"
        return "<div class=\"cmtcard\"><div class=\"cmtmeta\">\(badge)\(where_)\(del)</div>"
            + "<div class=\"cmtbody\">\(esc(c.comment.body))</div></div>"
    }

    /// unified diff 줄들 → 색칠된 diff 뷰(줄 앞 문자로 add/del/hunk/meta 구분).
    /// `stageable`이면 hunk(@@ 헤더)마다 '스테이지' 버튼을 붙이고, 클릭 시 hunk 인덱스를 Swift로 postMessage 한다.
    /// `discardable`이면 같은 hunk에 '버리기' 버튼을 붙여 muxaDiscard 채널로 hunk 인덱스를 보낸다(파괴적, Swift가 확인).
    /// `aggregate`(통합 diff)면 `diff --git` 경계마다 파일 경로 sticky 헤더를 세워 여러 파일을 한 번에 훑게 한다.
    /// `commentable`이면 각 내용 줄에 hover '＋' 코멘트 버튼을 달고, `comments`(재앵커링됨)를 줄 아래 카드로 얹는다.
    /// `sideBySide`면 통합 뷰 대신 2열(좌 old / 우 new) 나란히 보기로 렌더한다(코멘트는 통합 뷰 전용).
    static func diff(lines: [String], dark: Bool, stageable: Bool = false, discardable: Bool = false,
                     aggregate: Bool = false, commentable: Bool = false, comments: [AnchoredComment] = [],
                     sideBySide: Bool = false) -> String {
        if sideBySide { return diffTwoColumn(lines: lines, dark: dark, stageable: stageable, discardable: discardable) }
        let t = Theme.of(dark: dark)
        // 앵커된 코멘트는 배치 키로, 오래된 코멘트는 상단 배너로.
        var placed: [String: [AnchoredComment]] = [:]
        var outdated: [AnchoredComment] = []
        for c in comments {
            if let ln = c.resolvedLine, c.status != .outdated {
                placed[placementKey(file: c.comment.file, side: c.comment.side, line: ln), default: []].append(c)
            } else {
                outdated.append(c)
            }
        }
        // 코멘트 가능 줄의 앵커 정보(파일·side·줄번호·내용) — 재앵커링과 같은 규칙을 공유.
        let info = commentable ? ReviewCommentAnchor.indexLines(lines) : [:]

        var body = ""
        if !outdated.isEmpty {
            body += "<div class=\"outdatedwrap\"><div class=\"outdatedttl\">위치를 잃은 코멘트 \(outdated.count)개</div>"
            for c in outdated.sorted(by: { $0.comment.seq < $1.comment.seq }) { body += card(c, theme: t) }
            body += "</div>"
        }
        var hunkIndex = -1
        for (i, line) in lines.enumerated() {
            if aggregate, line.hasPrefix("diff ") {
                // 파일 경계 — sticky 헤더로 경로를 세우고 원본 `diff --git` 줄은 생략(중복 제거).
                body += "<div class=\"filehdr\">\(esc(ReviewCommentAnchor.filePath(fromDiffHeader: line)))</div>"
                continue
            }
            if line.hasPrefix("@@") {
                hunkIndex += 1
                let text = "<span class=\"hunktext\">\(esc(line))</span>"
                let btns = hunkButtons(index: hunkIndex, stageable: stageable, discardable: discardable)
                body += "<div class=\"dl hunk hunkrow\">\(btns)\(text)</div>"
                continue
            }
            let cls: String
            if line.hasPrefix("+++") || line.hasPrefix("---") { cls = "meta" }
            else if line.hasPrefix("+") { cls = "add" }
            else if line.hasPrefix("-") { cls = "del" }
            else if line.hasPrefix("@") { cls = "hunk" }
            else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("new ") || line.hasPrefix("deleted ") { cls = "meta" }
            else { cls = "" }
            if let li = info[i] {
                // 코멘트 가능 내용 줄 — 앵커 data-* + hover '＋' 버튼.
                let attrs = "data-file=\"\(escAttr(li.file))\" data-side=\"\(li.side.rawValue)\""
                    + " data-line=\"\(li.keyLine)\" data-text=\"\(escAttr(li.text))\""
                let btn = "<button class=\"cmtbtn\" onclick=\"muxaAddComment(this.parentNode)\" title=\"코멘트 달기\">＋</button>"
                body += "<div class=\"dl \(cls) cmtline\" \(attrs)>\(btn)\(esc(line.isEmpty ? " " : line))</div>"
                for c in placed[placementKey(file: li.file, side: li.side, line: li.keyLine)] ?? [] {
                    body += card(c, theme: t)
                }
            } else {
                body += "<div class=\"dl \(cls)\">\(esc(line.isEmpty ? " " : line))</div>"
            }
        }
        let cmtHandler = CodeWebView.commentMessageName
        var script = "<script>"
        script += minimapInit
        script += hunkScript(stageable: stageable, discardable: discardable)
        if commentable {
            script += """
            function muxaAddComment(el){try{window.webkit.messageHandlers.\(cmtHandler).postMessage(\
            {action:'add',file:el.getAttribute('data-file'),side:el.getAttribute('data-side'),\
            line:parseInt(el.getAttribute('data-line'),10),text:el.getAttribute('data-text')});}catch(e){}}
            function muxaDeleteComment(id){try{window.webkit.messageHandlers.\(cmtHandler).postMessage(\
            {action:'delete',id:id});}catch(e){}}
            """
        }
        script += "</script>"
        return page(body, theme: t, script: script)
    }

    /// 나란히 보기(2열) diff — SideBySideDiff 행 모델을 좌(old)/우(new) 표로 렌더. 통합 뷰 스타일·색 재사용.
    /// `stageable`/`discardable`이면 hunk 헤더 행에 통합 뷰와 같은 스테이지·버리기 버튼(브리지)을 붙인다.
    private static func diffTwoColumn(lines: [String], dark: Bool, stageable: Bool, discardable: Bool) -> String {
        let t = Theme.of(dark: dark)
        var body = "<table class=\"sxs\"><colgroup><col class=\"cln\"><col><col class=\"cln\"><col></colgroup>"
        for row in SideBySideDiff.rows(lines) {
            switch row {
            case .file(let path):
                body += "<tr><td colspan=\"4\" class=\"filehdr\">\(esc(path))</td></tr>"
            case let .hunk(text, index):
                let txt = "<span class=\"hunktext\">\(esc(text))</span>"
                let btns = hunkButtons(index: index, stageable: stageable, discardable: discardable)
                if btns.isEmpty {
                    body += "<tr><td colspan=\"4\" class=\"hunkhdr\">\(txt)</td></tr>"
                } else {
                    body += "<tr><td colspan=\"4\" class=\"hunkhdr\"><div class=\"hunkrow\">\(btns)\(txt)</div></td></tr>"
                }
            case let .pair(left, right):
                body += "<tr>\(cell(left, isLeft: true))\(cell(right, isLeft: false))</tr>"
            }
        }
        body += "</table>"
        let script = "<script>\(minimapInit)\(hunkScript(stageable: stageable, discardable: discardable))</script>"
        return page(body, theme: t, script: script)
    }


    /// 변경 위치 레일 스크립트 — `Resources/diffdoc/minimap.js` **한 파일이 단일 출처**다.
    /// 문서 diff 뷰어는 그 파일을 `<script src>`로 읽고, 여기서는 인라인한다
    /// (`CodeWebView`가 `loadHTMLString(baseURL: nil)`이라 외부 리소스를 못 읽기 때문).
    private static let minimapSource: String = {
        guard let url = Bundle.module.url(forResource: "minimap", withExtension: "js", subdirectory: "diffdoc"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return src
    }()

    /// 통합·나란히 뷰의 변경 위치 레일 초기화. 변경 줄(.add/.del)마다 틱을 찍는다.
    private static var minimapInit: String {
        guard !minimapSource.isEmpty else { return "" }
        return minimapSource + """
        \ntry{MuxaMinimap.watch('td.src.add,td.src.del,.dl.add,.dl.del', function(el){
          return el.classList.contains('add') ? 'add' : 'del'; });}catch(e){}
        """
    }

    /// hunk 헤더에 붙는 스테이지·버리기 버튼 HTML(없으면 빈 문자열). 통합·나란히 뷰가 공유.
    private static func hunkButtons(index: Int, stageable: Bool, discardable: Bool) -> String {
        var s = ""
        if stageable {
            s += "<button class=\"stagebtn\" onclick=\"muxaStageHunk(\(index))\">＋ 스테이지</button>"
        }
        if discardable {
            s += "<button class=\"discardbtn\" onclick=\"muxaDiscardHunk(\(index))\">↩︎ 버리기</button>"
        }
        return s
    }

    /// hunk 버튼이 부르는 postMessage 브리지 함수 정의(스테이지·버리기). 통합·나란히 뷰가 공유.
    private static func hunkScript(stageable: Bool, discardable: Bool) -> String {
        var s = ""
        if stageable {
            s += "function muxaStageHunk(i){try{window.webkit.messageHandlers.\(CodeWebView.messageName).postMessage(i);}catch(e){}}"
        }
        if discardable {
            s += "function muxaDiscardHunk(i){try{window.webkit.messageHandlers.\(CodeWebView.discardMessageName).postMessage(i);}catch(e){}}"
        }
        return s
    }

    /// 나란히 보기 한쪽 열의 두 셀(줄번호 + 내용). 비어 있으면(짝 없음) 회색 filler.
    private static func cell(_ c: SideBySideDiff.Cell?, isLeft: Bool) -> String {
        let divider = isLeft ? " midsrc" : ""
        guard let c else {
            return "<td class=\"ln empty\"></td><td class=\"src empty\(divider)\"></td>"
        }
        let kindCls: String
        switch c.kind {
        case .add: kindCls = " add"
        case .del: kindCls = " del"
        case .context: kindCls = ""
        }
        let content = esc(c.text.isEmpty ? " " : c.text)
        return "<td class=\"ln\">\(c.lineNo)</td><td class=\"src\(kindCls)\(divider)\">\(content)</td>"
    }
}
