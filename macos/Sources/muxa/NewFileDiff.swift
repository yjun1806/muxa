import Foundation

/// unified diff가 **새로 생긴 파일**인지 판정한다(순수).
///
/// 새 파일은 "이전"이 없다. 그래서 diff가 할 말이 없는데도 관례상 모든 줄이 초록으로 칠해진다 —
/// 42줄이면 42번 반복되는데 정보량은 헤더 한 줄과 같다. 이 저장소는 이 실패를 이미 알고 있다:
/// `DocDiffSource`가 리네임 버그의 증상을 "diff가 통째로 초록이 된다"로 적어놨다.
///
/// **추가됐다는 사실은 한 번만 말하면 된다** — 본문은 문서·코드 그대로 렌더하고,
/// 새 파일이라는 사실은 헤더 배지 하나가 진다.
enum NewFileDiff {
    /// 옛쪽이 비어 있는가.
    ///
    /// 두 형태를 본다. `git diff <rev> -- <path>`는 헤더에 `new file mode`를 싣고,
    /// 추적 안 되는 파일의 `--no-index` diff는 `--- /dev/null`을 싣는다.
    ///
    /// **`+++ /dev/null`과 혼동하지 않는다** — 그건 새쪽이 비었다는 뜻이라 *삭제*다.
    /// 접두만 보고 `/dev/null`을 세면 삭제된 파일을 새 파일로 그린다.
    static func isNewFile(_ lines: [String]) -> Bool {
        for line in lines {
            if line.hasPrefix("new file mode") { return true }
            if line.hasPrefix("--- /dev/null") { return true }
            // 본문에 들어서면 헤더는 끝났다 — 뒤는 볼 필요가 없다(큰 diff 조기 종료).
            if line.hasPrefix("@@") { return false }
        }
        return false
    }

    /// 본문 줄 수(헤더·메타 제외) — "새 파일 · 42줄" 배지가 쓴다.
    /// `+++`(파일 헤더)는 세지 않는다.
    static func addedLineCount(_ lines: [String]) -> Int {
        lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
    }
}
