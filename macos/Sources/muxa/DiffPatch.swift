import Foundation

/// 단일 파일 unified diff → 헤더(첫 @@ 이전) + hunk들로 분해하고, hunk 하나만 담은 패치를 구성한다.
/// 이 패치를 `git apply --cached`에 stdin으로 넣으면 hunk 단위 스테이지가 된다(`git add -p`와 같은 의미).
/// 부작용 없는 순수 함수라 테스트·재사용이 쉽다.
enum DiffPatch {
    /// diff를 헤더와 hunk 배열로 나눈 결과.
    struct Parsed {
        let header: [String]    // "diff --git" / "index" / "--- a/…" / "+++ b/…" 등
        let hunks: [[String]]   // 각 원소가 "@@ …"로 시작하는 한 hunk의 줄들
    }

    /// diff 줄들을 헤더 + hunk 배열로 분해. "@@"로 시작하는 줄이 새 hunk의 시작.
    static func parse(_ lines: [String]) -> Parsed {
        var header: [String] = []
        var hunks: [[String]] = []
        var current: [String]?
        for line in lines {
            if line.hasPrefix("@@") {
                if let cur = current { hunks.append(cur) }
                current = [line]
            } else if current == nil {
                header.append(line)
            } else {
                current?.append(line)
            }
        }
        if let cur = current { hunks.append(cur) }
        return Parsed(header: header, hunks: hunks)
    }

    /// hunk 하나만 담은 패치(헤더 + 해당 hunk, 개행 종료). 인덱스 밖이거나 헤더가 부적합하면 nil.
    static func patch(forHunk index: Int, in parsed: Parsed) -> String? {
        guard parsed.hunks.indices.contains(index), headerIsApplicable(parsed.header) else { return nil }
        // 마지막 요소의 빈 문자열(split 아티팩트)만 제거 — 실제 diff 줄은 최소 접두 문자를 가져 ""가 아니다.
        var body = parsed.header + parsed.hunks[index]
        while body.last == "" { body.removeLast() }
        return body.joined(separator: "\n") + "\n"
    }

    /// `git apply`가 요구하는 파일 헤더(--- / +++)가 있는지 — untracked(--no-index) diff는 걸러진다.
    static func headerIsApplicable(_ header: [String]) -> Bool {
        header.contains { $0.hasPrefix("--- ") } && header.contains { $0.hasPrefix("+++ ") }
    }

    /// hunk 개수(버튼 노출 판단용).
    static func hunkCount(_ lines: [String]) -> Int {
        lines.reduce(0) { $0 + ($1.hasPrefix("@@") ? 1 : 0) }
    }
}
