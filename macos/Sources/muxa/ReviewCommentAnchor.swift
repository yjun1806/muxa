import Foundation

/// unified diff 한 줄의 앵커 정보 — 어느 파일·어느 쪽·줄번호·내용. 코멘트 배치와 재앵커링이 공유하는 순수 파생값.
struct DiffLineInfo: Equatable {
    let file: String
    let side: DiffSide
    /// add/context는 새 파일 줄번호, del은 옛 파일 줄번호.
    let keyLine: Int
    /// 접두 문자(+/-/공백)를 뗀 줄 내용.
    let text: String
}

/// diff 줄 재앵커링·인덱싱 순수 로직. 부작용 없어 테스트·재사용이 쉽다.
/// CodeHTML(코멘트 카드 배치)과 재앵커링(anchored/moved/outdated)이 같은 줄번호 규칙을 쓰도록 여기 한 곳에 둔다.
enum ReviewCommentAnchor {
    /// `diff --git a/… b/…` / `+++ b/…` 헤더에서 표시용 파일 경로(b/ 새 경로 우선)를 뽑는다.
    static func filePath(fromDiffHeader line: String) -> String {
        if let r = line.range(of: " b/") { return String(line[r.upperBound...]) }
        return line.split(separator: " ").last.map(String.init) ?? line
    }

    /// `+++ b/path` → path(리네임/삭제 대비). `+++ /dev/null`처럼 b/가 없으면 nil.
    static func filePath(fromPlusHeader line: String) -> String? {
        guard let r = line.range(of: "+++ b/") else { return nil }
        return String(line[r.upperBound...])
    }

    /// `@@ -oldStart,oldCount +newStart,newCount @@` → (oldStart, newStart). 파싱 실패면 nil.
    static func hunkStarts(_ line: String) -> (old: Int, new: Int)? {
        // "@@ -a,b +c,d @@ …" 에서 -a 와 +c 를 뽑는다(카운트는 무시).
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[0] == "@@" else { return nil }
        func firstNumber(_ token: Substring, sign: Character) -> Int? {
            guard token.first == sign else { return nil }
            let body = token.dropFirst() // "a,b" 또는 "a"
            let num = body.split(separator: ",").first ?? body
            return Int(num)
        }
        guard let old = firstNumber(parts[1], sign: "-"),
              let new = firstNumber(parts[2], sign: "+") else { return nil }
        return (old, new)
    }

    /// 원본 diff 줄 배열(index → 앵커 정보) — 코멘트 가능한 내용 줄만 담는다(헤더·hunk·meta 제외).
    /// CodeHTML이 렌더하며 raw index로 조회하고, 재앵커링이 파일별 후보 목록을 만드는 데 쓴다.
    static func indexLines(_ lines: [String]) -> [Int: DiffLineInfo] {
        var result: [Int: DiffLineInfo] = [:]
        var file = ""
        var oldCursor = 0
        var newCursor = 0
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("diff ") {
                file = filePath(fromDiffHeader: line)
                continue
            }
            if line.hasPrefix("+++ ") {
                if let f = filePath(fromPlusHeader: line) { file = f }
                continue
            }
            if line.hasPrefix("--- ") { continue }      // 옛 파일 헤더(--- a/… / --- /dev/null)
            if line.hasPrefix("@@") {
                if let s = hunkStarts(line) { oldCursor = s.old; newCursor = s.new }
                continue
            }
            if line.hasPrefix("\\") { continue }         // "\ No newline at end of file"
            guard let first = line.first else {          // 빈 줄 = 문맥(공백) 줄
                result[i] = DiffLineInfo(file: file, side: .context, keyLine: newCursor, text: "")
                oldCursor += 1; newCursor += 1
                continue
            }
            switch first {
            case "+":
                result[i] = DiffLineInfo(file: file, side: .add, keyLine: newCursor, text: String(line.dropFirst()))
                newCursor += 1
            case "-":
                result[i] = DiffLineInfo(file: file, side: .del, keyLine: oldCursor, text: String(line.dropFirst()))
                oldCursor += 1
            case " ":
                result[i] = DiffLineInfo(file: file, side: .context, keyLine: newCursor, text: String(line.dropFirst()))
                oldCursor += 1; newCursor += 1
            default:
                continue // index/new file/deleted 등 meta
            }
        }
        return result
    }

    /// 저장된 코멘트들을 현재 diff 줄에 재앵커링한다.
    /// - anchored: 저장 위치(file·side·line·text)가 그대로 있으면 저장 줄에 그대로.
    /// - moved: 저장 위치엔 없지만 그 파일 diff 안에 같은 side·text 줄이 정확히 하나면 그 줄로 옮긴다.
    /// - outdated: 없거나 둘 이상이면 위치 불명(상단 배너).
    static func resolve(_ comments: [ReviewComment], lines: [String]) -> [AnchoredComment] {
        let infos = Array(indexLines(lines).values)
        return comments.map { c in
            let candidates = infos.filter { $0.file == c.file && $0.side == c.side && $0.text == c.lineText }
            if candidates.contains(where: { $0.keyLine == c.line }) {
                return AnchoredComment(comment: c, status: .anchored, resolvedLine: c.line)
            }
            if candidates.count == 1 {
                return AnchoredComment(comment: c, status: .moved, resolvedLine: candidates[0].keyLine)
            }
            return AnchoredComment(comment: c, status: .outdated, resolvedLine: nil)
        }
    }
}
