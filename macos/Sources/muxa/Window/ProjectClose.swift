import AppKit

/// 프로젝트 닫기의 **유일한 진입점**(사이드바 ✕ · 우클릭 메뉴).
///
/// `AppState.closeProject`는 파괴적이다 — 서비스(dev 서버)와 tmux 세션을 함께 죽인다.
/// 그 프로젝트가 **분리 창**에 있으면 그건 지금 화면 밖에서 돌고 있는 에이전트라는 뜻이라,
/// 메인 창의 ✕ 한 번으로 몰살시키지 않게 그때만 한 번 묻는다(파괴는 좁게 — CLAUDE.md).
/// 메인 창의 프로젝트는 눈앞에 있으므로 오늘과 같이 묻지 않고 닫는다.
@MainActor
enum ProjectClose {
    static func request(_ project: Project, state: AppState) {
        guard confirmIfSeparated(project, state: state) else { return }
        state.closeProject(project.id)
    }

    private static func confirmIfSeparated(_ project: Project, state: AppState) -> Bool {
        guard !state.owner(of: project.id).isMain else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(project.name)을(를) 닫을까요?"
        alert.informativeText = "다른 창에서 실행 중입니다 — 닫으면 서비스와 터미널 세션이 모두 종료됩니다."
        alert.addButton(withTitle: "닫기") // 첫 버튼 = 기본(Enter)
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
