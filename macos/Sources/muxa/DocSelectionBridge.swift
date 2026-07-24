import Foundation

/// 문서 WebView(마크다운·코드 뷰어)의 텍스트 선택을 IDE 통합으로 나르는 브리지.
/// - `js`: WebView에 주입하는 selectionchange 리스너(디바운스 + 중복 억제). 선택/해제를 postMessage로 보낸다.
/// - `selection(from:filePath:)`: JS가 보낸 메시지(dict) + 뷰가 아는 파일 경로 → IdeSelection(순수·테스트).
///
/// 줄/문자 좌표는 **렌더된 본문 텍스트** 기준의 0-기반 값이다. 코드 뷰어(highlight.js는 개행 보존)에선
/// 소스 줄과 거의 일치하고, 마크다운(렌더 HTML)에선 근사값이다 — 텍스트·파일 경로는 항상 정확하다.
enum DocSelectionBridge {
    static let messageName = "muxaSelection"

    /// 메시지 body → IdeSelection. body가 dict가 아니면 nil.
    static func selection(from body: Any, filePath: String) -> IdeSelection? {
        guard let d = body as? [String: Any] else { return nil }
        func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        return IdeSelection(filePath: filePath,
                            text: d["text"] as? String ?? "",
                            startLine: int("startLine"), startCharacter: int("startChar"),
                            endLine: int("endLine"), endCharacter: int("endChar"))
    }

    /// selectionchange를 감시해 선택(또는 해제)을 postMessage로 보내는 주입 스크립트. 두 번 걸리지 않게 가드.
    static let js = #"""
    (function(){
      if (window.__muxaSel) return; window.__muxaSel = true;
      function at(container, node, off){
        var r = document.createRange(); r.selectNodeContents(container); r.setEnd(node, off);
        var s = r.toString();
        return { line: (s.match(/\n/g)||[]).length, ch: s.length - (s.lastIndexOf("\n")+1) };
      }
      var last = "";
      function send(o){
        var key = o.text + "|" + o.startLine + "|" + o.endLine;
        if (key === last) return; last = key;
        try { window.webkit.messageHandlers.muxaSelection.postMessage(o); } catch(e){}
      }
      function post(){
        try {
          var sel = window.getSelection(), body = document.body;
          if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
            send({text:"", startLine:0, startChar:0, endLine:0, endChar:0}); return;
          }
          var r = sel.getRangeAt(0), a = at(body, r.startContainer, r.startOffset), b = at(body, r.endContainer, r.endOffset);
          send({text: sel.toString(), startLine:a.line, startChar:a.ch, endLine:b.line, endChar:b.ch});
        } catch(e){}
      }
      document.addEventListener('selectionchange', function(){
        clearTimeout(window.__muxaSelT); window.__muxaSelT = setTimeout(post, 150);
      });
    })();
    """#
}
