import SwiftUI

/// GitHub PR 상태와 CI 롤업의 표시 규칙 — 색·글리프·라벨의 단일 출처.
/// `ServiceStatusStyle`·`ScriptStatusStyle`·`GitStatusStyle`과 같은 자리·같은 패턴이다
/// (예전엔 `GitPanel`의 private 함수 셋으로 흩어져 있어 뷰를 쪼개면 따라다녀야 했다).
///
/// **PR 상태와 CI는 다른 축이다.** 하나의 알약 안에 뭉치면 알약이 "OPEN(초록)"이라 말하는 동안
/// 내용물이 "실패(빨강)"라 말한다 — `Pill`은 "색 하나만 정하면 배경 틴트가 따라온다"는 컴포넌트라
/// 두 색이 싸우면 규칙이 깨진다. 그래서 알약은 PR 상태만 담고 CI는 **밖에** 독립 글리프로 둔다.
enum PRStatusStyle {

    // MARK: PR 상태

    /// open/closed는 git 추가·삭제색을 재사용하고, merged만 전용 보라(관례색).
    static func color(_ state: String) -> Color {
        switch state.uppercased() {
        case "OPEN": return Color(nsColor: Palette.gitAdded)
        case "MERGED": return Color(nsColor: Palette.prMerged)
        case "CLOSED": return Color(nsColor: Palette.gitDeleted)
        default: return .pMuted
        }
    }

    /// 스크린리더용 — 배지에 `.help()`만 있으면 VoiceOver는 "arrow.triangle.pull"로 읽는다.
    static func label(_ state: String) -> String {
        switch state.uppercased() {
        case "OPEN": return "열림"
        case "MERGED": return "머지됨"
        case "CLOSED": return "닫힘"
        default: return state
        }
    }

    /// PR 축의 대표 글리프.
    static let icon = "arrow.triangle.pull"

    // MARK: CI 롤업

    static func checkColor(_ check: GitService.GHStatus.Check) -> Color {
        switch check {
        case .passing: return Color(nsColor: Palette.gitAdded)
        case .failing: return Color(nsColor: Palette.gitDeleted)
        case .pending: return Color(nsColor: Palette.gitModified)
        }
    }

    /// **색만으로 구분하지 않는다** — 결과가 갈리면 글리프 자체가 바뀐다(색맹 안전).
    static func checkGlyph(_ check: GitService.GHStatus.Check) -> String {
        switch check {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .pending: return "circle.dotted"
        }
    }

    static func checkLabel(_ check: GitService.GHStatus.Check) -> String {
        switch check {
        case .passing: return "CI 통과"
        case .failing: return "CI 실패"
        case .pending: return "CI 진행 중"
        }
    }
}
