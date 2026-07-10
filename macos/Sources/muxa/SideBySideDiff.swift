import Foundation

/// unified diff 줄들 → 2열(좌 old / 우 new) 나란히 보기용 행 모델로 재구성하는 순수 로직.
/// 부작용 없음 — CodeHTML이 이 행 모델을 HTML 표로 렌더한다(외부 의존성 0).
///
/// 정렬 규칙(GitHub 스타일): 연속된 삭제(-)와 추가(+) 묶음을 짝지어 같은 행의 좌/우에 놓는다.
/// 삭제가 더 많으면 남는 삭제는 우측이 비고, 추가가 더 많으면 남는 추가는 좌측이 빈다.
/// 문맥(공백) 줄은 양쪽에 같은 내용으로 놓되 줄번호만 old/new로 다르다.
enum SideBySideDiff {
    /// diff 한 칸(한쪽 열의 한 줄). 줄번호·접두 뗀 내용·종류.
    struct Cell: Equatable {
        let lineNo: Int
        let text: String
        let kind: Kind
    }

    enum Kind: Equatable { case context, del, add }

    /// 표의 한 행 — 파일 경계 헤더 / hunk 헤더(스테이지 인덱스 포함) / 좌우 짝.
    enum Row: Equatable {
        case file(String)
        case hunk(text: String, index: Int)
        case pair(left: Cell?, right: Cell?)
    }

    /// unified diff 줄 배열 → 나란히 보기 행 배열. `ReviewCommentAnchor`와 같은 줄번호 규칙을 따른다.
    static func rows(_ lines: [String]) -> [Row] {
        var result: [Row] = []
        var oldCursor = 0
        var newCursor = 0
        var hunkIndex = -1
        var pendingDel: [Cell] = []
        var pendingAdd: [Cell] = []

        func flush() {
            let n = max(pendingDel.count, pendingAdd.count)
            for i in 0..<n {
                let l = i < pendingDel.count ? pendingDel[i] : nil
                let r = i < pendingAdd.count ? pendingAdd[i] : nil
                result.append(.pair(left: l, right: r))
            }
            pendingDel.removeAll(keepingCapacity: true)
            pendingAdd.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("diff ") {
                flush()
                result.append(.file(ReviewCommentAnchor.filePath(fromDiffHeader: line)))
                continue
            }
            if line.hasPrefix("@@") {
                flush()
                hunkIndex += 1
                if let s = ReviewCommentAnchor.hunkStarts(line) { oldCursor = s.old; newCursor = s.new }
                result.append(.hunk(text: line, index: hunkIndex))
                continue
            }
            // 파일 메타 헤더(경로는 file 헤더가 이미 세움) — 삼킨다.
            if line.hasPrefix("+++ ") || line.hasPrefix("--- ") || line.hasPrefix("index ")
                || line.hasPrefix("new ") || line.hasPrefix("deleted ") || line.hasPrefix("old ")
                || line.hasPrefix("rename ") || line.hasPrefix("similarity ") || line.hasPrefix("copy ") {
                continue
            }
            if line.hasPrefix("\\") { continue } // "\ No newline at end of file"

            guard let first = line.first else {
                // 빈 줄 = 문맥(공백) 줄 — 양쪽 동일.
                flush()
                result.append(.pair(left: Cell(lineNo: oldCursor, text: "", kind: .context),
                                    right: Cell(lineNo: newCursor, text: "", kind: .context)))
                oldCursor += 1; newCursor += 1
                continue
            }
            switch first {
            case "+":
                pendingAdd.append(Cell(lineNo: newCursor, text: String(line.dropFirst()), kind: .add))
                newCursor += 1
            case "-":
                pendingDel.append(Cell(lineNo: oldCursor, text: String(line.dropFirst()), kind: .del))
                oldCursor += 1
            case " ":
                flush()
                let text = String(line.dropFirst())
                result.append(.pair(left: Cell(lineNo: oldCursor, text: text, kind: .context),
                                    right: Cell(lineNo: newCursor, text: text, kind: .context)))
                oldCursor += 1; newCursor += 1
            default:
                continue // 그 외 meta는 무시
            }
        }
        flush()
        return result
    }
}
