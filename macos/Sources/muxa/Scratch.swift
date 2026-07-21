import Foundation

/// 프로젝트-없는 "스크래치"(~) 공간 — workspace/projectWindows 시스템 **밖**의 완전 독립 창+store.
/// $HOME에서 시작한다. 상단바 우측 버튼·⌘⌥T가 별도 창으로 연다.
///
/// **고정 상수 id (CRITICAL): newId() 절대 금지.** layout·tmux 세션 키는 `projectId` 상수라
/// 워크스페이스 소속과 무관하게 재시작·창 닫기에도 산다(매 실행 새 id면 세션이 고아로 판정돼 사망).
enum Scratch {
    /// **레거시 마이그레이션 전용.** 2차 pivot 이전 저장분은 스크래치를 `workspaces[0]`에 넣어 뒀다 —
    /// 로드 시 `stripLegacyWorkspace`가 이 id로 그 유령 워크스페이스를 걷어낸다(그 목적에만 남는다).
    static let workspaceId = "muxa.scratch"
    static let projectId = "muxa.scratch.home"
    static let label = "~"
    /// 스크래치 터미널이 사는 **독립 창**의 고정 id — `projectWindows`/`sync` 밖에서 이 id로 창을 만든다.
    /// 상수라 재시작 시 열림 상태·프레임이 복원되고, tmux/layout 키(projectId)와 함께 세션이 산다.
    static let windowId = WindowID(rawValue: "muxa.scratch.window")

    static func isScratchWorkspace(_ id: String) -> Bool { id == workspaceId }

    /// 구 저장분의 스크래치 워크스페이스를 걷어낸다(순수·멱등). 스크래치는 이제 `workspaces`에 없다 —
    /// 남아 있으면 사이드바에 유령 "~"가 뜬다. `activeId`가 스크래치였으면 첫 실 워크스페이스로 폴백.
    /// (layout/tmux 키는 `projectId` 상수라 workspaces와 무관하게 산다 — 여기서 건드리지 않는다.)
    static func stripLegacyWorkspace(_ workspaces: [Workspace], activeId: String)
        -> (workspaces: [Workspace], activeId: String) {
        let stripped = workspaces.filter { !isScratchWorkspace($0.id) }
        let nextActive = isScratchWorkspace(activeId) ? (stripped.first?.id ?? "") : activeId
        return (stripped, nextActive)
    }
}
