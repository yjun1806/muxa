import Foundation

/// 외부 의존성 없는 순수 퍼지 매칭 — 부분 서열(subsequence) 스코어링.
/// 쿼리의 모든 문자가 순서대로 텍스트에 나타나야 매치. 점수는 높을수록 좋다.
/// 연속 매치·단어 경계·맨 앞 매치에 가산점, 뒤쪽 매치엔 소폭 감점을 준다.
/// (⌘K 빠른 전환기 랭킹의 단일 진실 원천 — 테스트 가능하도록 뷰와 분리.)
enum FuzzyMatch {
    /// 대소문자 무시. 쿼리가 비면 항상 매치(점수 0). 부분 서열이 아니면 nil.
    static func score(query: String, in text: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let hay = Array(text)
        let low = Array(text.lowercased())
        guard hay.count >= q.count else { return nil }

        var qi = 0
        var total = 0
        var prevMatch = -2
        for i in low.indices where qi < q.count {
            guard low[i] == q[qi] else { continue }
            var bonus = 10
            if i == prevMatch + 1 { bonus += 15 }   // 연속 매치(단어 통째로 맞으면 크게 유리)
            if isBoundary(hay, i) { bonus += 20 }    // 단어 경계(첫 글자·구분자 뒤·camelCase 전이)
            if i == 0 { bonus += 15 }                // 맨 앞 글자
            bonus -= min(i, 10)                      // 뒤쪽에서 시작할수록 소폭 감점
            total += bonus
            prevMatch = i
            qi += 1
        }
        return qi == q.count ? total : nil
    }

    /// 단어 경계인가 — 맨 앞이거나, 앞 글자가 구분자거나, 소문자→대문자 전이(camelCase).
    private static func isBoundary(_ chars: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let prev = chars[i - 1]
        if prev == " " || prev == "/" || prev == "_" || prev == "-" || prev == "." { return true }
        if prev.isLowercase, chars[i].isUppercase { return true }
        return false
    }
}
