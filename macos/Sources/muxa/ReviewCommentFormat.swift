import Foundation

/// 리뷰 코멘트 묶음 → 포커스 터미널에 붙일 지시 텍스트로 포맷하는 순수 함수.
/// 에이전트가 다음 턴에 읽을 형식: 파일:줄 + 앵커 줄 내용 + 코멘트 본문. 부작용 없음.
enum ReviewCommentFormat {
    /// 코멘트들을 한 덩어리 지시문으로 만든다. 파일별로 묶고 줄번호 순 정렬. 빈 목록이면 "".
    /// 끝에 개행을 붙이지 않는다 — 실행(Enter) 커밋은 호출부가 sendText 개행 규칙으로 판단한다.
    static func instruction(_ comments: [ReviewComment]) -> String {
        guard !comments.isEmpty else { return "" }
        var out = "다음 \(comments.count)개의 코드 리뷰 코멘트를 반영해줘:\n"
        let byFile = Dictionary(grouping: comments, by: \.file)
        for file in byFile.keys.sorted() {
            out += "\n[\(file)]\n"
            let items = (byFile[file] ?? []).sorted { $0.line < $1.line }
            for c in items {
                let anchor = c.lineText.trimmingCharacters(in: .whitespaces)
                out += "- \(c.line)번째 줄"
                if !anchor.isEmpty { out += " (\(anchor))" }
                out += ": \(c.body)\n"
            }
        }
        return out
    }
}
