import AppKit

/// 프로젝트 닫기의 **판정**(순수) — 바로 닫을 것인가, 물을 것인가.
///
/// `AppState.closeProject`는 파괴적이다 — 서비스(dev 서버)와 tmux 세션을 함께 죽인다.
/// 판정을 NSAlert(경계)와 한 함수에 섞어 두면 자동 검증이 하나도 못 붙어, 조건이 뒤집혀도
/// (예: "메인이어도 서비스가 살아 있으면 묻는다"로 확장) 아무도 잡지 못한다 —
/// 판정은 값으로, 삭제·시트는 경계에만(CLAUDE.md: 파괴는 좁게, 보존은 넓게).
enum ProjectCloseDecision: Equatable {
    /// 눈앞(메인 창)의 프로젝트 — 묻지 않고 닫는다.
    case closeNow
    /// 분리 창에서 돌고 있다 = 화면 밖의 에이전트 — ✕ 한 번으로 몰살시키지 않게 묻는다.
    case confirm

    static func decide(separated: Bool) -> ProjectCloseDecision {
        separated ? .confirm : .closeNow
    }
}

/// 프로젝트 닫기의 **유일한 진입점**(사이드바 ✕ · 우클릭 메뉴) — 판정을 받아 시트만 띄운다.
@MainActor
enum ProjectClose {
    static func request(_ project: Project, state: AppState) {
        let decision = ProjectCloseDecision.decide(separated: !state.owner(of: project.id).isMain)
        if decision == .confirm, !confirm(project) { return }
        state.closeProject(project.id)
    }

    private static func confirm(_ project: Project) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(project.name)을(를) 닫을까요?"
        alert.informativeText = "다른 창에서 실행 중입니다 — 닫으면 서비스와 터미널 세션이 모두 종료됩니다."
        alert.addButton(withTitle: "닫기") // 첫 버튼 = 기본(Enter)
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
