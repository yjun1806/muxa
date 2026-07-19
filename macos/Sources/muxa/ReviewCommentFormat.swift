import Foundation

/// 리뷰 코멘트 묶음 → 포커스 터미널에 붙일 지시 텍스트로 포맷하는 순수 함수.
/// 에이전트가 다음 턴에 읽을 형식: 파일:줄 + 앵커 줄 내용 + 코멘트 본문. 부작용 없음.
enum ReviewCommentFormat {
    /// 코멘트들을 한 덩어리 지시문으로 만든다. 파일별로 묶고 줄번호 순 정렬. 빈 목록이면 "".
    /// 끝에 개행을 붙이지 않는다 — 실행(Enter) 커밋은 호출부가 sendText 개행 규칙으로 판단한다.
    ///
    /// **커밋에 달린 코멘트는 해시를 함께 싣는다** — 안 그러면 에이전트가 줄번호만 받고 그 줄이
    /// 지금 워크트리의 어디인지 다시 찾아야 한다. 해시가 있으면 amend·fixup 대상을 스스로 판단한다.
    static func instruction(_ comments: [ReviewComment]) -> String {
        guard !comments.isEmpty else { return "" }
        var out = "다음 \(comments.count)개의 코드 리뷰 코멘트를 반영해줘:\n"
        // 커밋별로 먼저 가른다 — 워크트리(nil)가 앞, 그다음 해시 순.
        let byCommit = Dictionary(grouping: comments, by: \.commit)
        for commit in byCommit.keys.sorted(by: sortScope) {
            let scoped = byCommit[commit] ?? []
            if let commit {
                out += "\n=== 커밋 \(String(commit.prefix(7))) ===\n"
            } else if byCommit.count > 1 {
                out += "\n=== 아직 커밋 안 된 변경 ===\n" // 스코프가 하나뿐이면 머리글이 소음이다
            }
            let byFile = Dictionary(grouping: scoped, by: \.file)
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
        }
        return out
    }

    /// 스코프 정렬 — 워크트리(nil)가 먼저, 커밋은 해시 사전순(결정적이면 충분하다).
    private static func sortScope(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case (let x?, let y?): return x < y
        }
    }
}
