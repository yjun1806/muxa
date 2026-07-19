import SwiftUI

/// git 파일 상태의 표시 규칙 — 색·라벨의 단일 출처(**git 축 SSOT**).
/// Git 패널의 변경 파일 행·커밋 파일 행, 익스플로러 파일명 색이 전부 여기서 파생한다.
///
/// **표식은 GitHub식 diff 글리프다 — 사각형 안의 `+`·`·`·`−`·`→`.**
/// 개발자가 PR "Files changed"에서 매일 보는 관례라 학습 비용이 0이고, 문자 배지(`A`/`M`/`D`)보다
/// 주변시(周邊視)에서 빨리 갈린다 — 목록을 훑을 때 글자는 읽어야 하지만 도형은 안 읽어도 보인다.
///
/// **채움 vs 외곽선이 한 축을 더 나른다.** 추적되는 추가(`A`)는 채운 사각형, 추적 안 됨(`?`)은 빈
/// 사각형이다. 리네임(`R`)/복사(`C`)도 같은 규칙. 색은 "무슨 변경인가"를, 채움은 "git이 이미 아는
/// 파일인가"를 말해 두 정보가 두 채널로 갈린다.
///
/// **사각형은 스크립트 축(`ScriptStatusStyle`)과 껍데기를 공유한다 — 의도된 예외다.**
/// DESIGN §2의 "축끼리 글리프를 공유하지 않는다"는 **한 화면에 함께 뜨는** 상태 어휘를 위한 규칙이다
/// (푸터에 에이전트·서비스·스크립트가 나란히 선다). git 파일 상태는 **Git 패널 안에서만** 살고
/// 스크립트 상태는 푸터·도크에만 살아 같은 표면에서 마주치지 않는다. 게다가 안쪽 글리프가
/// 완전히 다르다 — 스크립트는 동작(▶ ✓ ✗ ?), git은 diff(+ · − →). 껍데기가 같아도 오독이 없다.
/// (예전엔 이 자리에 "문자를 유지한다"는 반대 결론이 적혀 있었다. 외부 관례의 힘과 스캔 속도가
/// 더 크다고 판단해 뒤집었다.)
///
/// **porcelain v1 원문이 정답이다.** 예전에 `GitFileStatus.badge`가 untracked를 `U`로,
/// conflict를 `C`로 내보냈는데 git에서 `U`=unmerged, `C`=copied라 의미가 정반대였다.
/// 그 필드는 소비처가 없어 화면엔 안 나왔지만, 세 번째 소비자(커밋 파일 행)가 생기는 지금
/// 되살아나면 진짜 버그가 된다 — 그래서 매핑을 여기 하나로 모으고 그 필드는 지웠다.
enum GitStatusStyle {

    /// 상태 문자 → SF Symbol. GitHub octicon(`diff-added`·`diff-modified`·`diff-removed`·`diff-renamed`)의 대응물.
    ///
    /// **색만으로 구분하지 않는다**(색맹 안전) — 추가·수정·삭제가 안쪽 기호(`+`·`·`·`−`)로 이미 갈린다.
    static func glyph(_ code: Character) -> String {
        switch code {
        case "A": return "plus.square.fill"          // 추가(추적됨)
        case "?": return "plus.square"               // 추적 안 됨 — 빈 사각형(git이 아직 모르는 파일)
        case "M", "T": return "dot.square.fill"      // 수정·타입 변경
        case "D": return "minus.square.fill"         // 삭제
        case "R": return "arrow.right.square.fill"   // 이름 변경
        case "C": return "arrow.right.square"        // 복사 — 리네임과 채움으로 가른다
        case "U": return "exclamationmark.triangle.fill" // 충돌 — 유일하게 사각형을 벗어난다(가장 센 신호)
        default: return "questionmark.square"        // 모르는 상태를 지어내지 않는다
        }
    }

    /// 상태 문자 → 색. 팔레트의 git 기능색만 쓴다(시스템색 `.green`류는 라이트/다크 대비가 어긋난다).
    ///
    /// `A`(추가)와 `?`(추적 안 됨)가 같은 초록인 건 의도다 — **색이 "새 파일"을, 문자가
    /// "스테이지됐나"를** 말해 두 정보가 두 채널로 갈린다.
    static func color(_ code: Character) -> Color {
        switch code {
        case "A", "?": return Color(nsColor: Palette.gitAdded)
        case "M", "T": return Color(nsColor: Palette.gitModified)
        case "D": return Color(nsColor: Palette.gitDeleted)
        case "R", "C": return Color(nsColor: Palette.gitRenamed)
        case "U": return Color(nsColor: Palette.gitConflict)
        default: return .pMuted
        }
    }

    /// 스크린리더용 상태 이름 — 색도 문자도 VoiceOver에는 존재하지 않는다(DESIGN §2 규칙).
    /// 아이콘만 있는 행이 20개면 전부 똑같이 들린다.
    static func label(_ code: Character) -> String {
        switch code {
        case "A": return "추가됨"
        case "?": return "추적 안 됨"
        case "M": return "수정됨"
        case "T": return "타입 변경됨"
        case "D": return "삭제됨"
        case "R": return "이름 변경됨"
        case "C": return "복사됨"
        case "U": return "충돌"
        default: return String(code)
        }
    }

    /// 충돌만 문자 슬롯에 옅은 배경 틴트를 준다 — **유일한 틴트라 그 자체가 신호**다.
    /// (다른 상태로 예외를 넓히면 축이 흔들리고 "색은 아껴 쓴다" 예산도 터진다.)
    static func isConflict(_ code: Character) -> Bool { code == "U" }

    /// 익스플로러 어댑터 — `GitFileStatus`(열거형)를 porcelain 문자로 환원해 위 테이블 하나만 거치게 한다.
    /// `ProjectStatusStyle`이 `StatusStyle`의 얇은 어댑터인 것과 같은 관계다.
    static func code(_ status: GitFileStatus) -> Character {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        case .conflict: return "U"
        }
    }

    /// 익스플로러 파일명 색 — 위 어댑터를 거쳐 같은 테이블에서 나온다.
    static func color(_ status: GitFileStatus) -> Color { color(code(status)) }
}
