import AppKit

/// 창 배치의 **경계** — 순수 판정은 `WindowLayout`이 하고, 여기서는 앱 상태(SSOT)에 반영한다.
/// 본체(AppState.swift)를 더 키우지 않기 위한 확장 파일.
///
/// 이 파일이 `projectWindows`를 바꾸는 **유일한 통로**다(`moveProjects`) — 그래야 모델⇄실물 정합(I4)을
/// 한 곳에서만 지키면 된다. 예외는 프로젝트가 사라지는 경로(removeWorkspace·closeProject)의 정리뿐이다.
@MainActor
extension AppState {
    // MARK: 조회 (총함수 — 유실 불가)

    /// 이 프로젝트를 그릴 창. 어느 분리 창에도 없으면 메인이다(I1).
    func owner(of projectId: String) -> WindowID {
        WindowLayout.owner(of: projectId, in: projectWindows)
    }

    /// 이 프로젝트를 품은 분리 창(메인이면 nil).
    func window(owning projectId: String) -> ProjectWindow? {
        projectWindows.first { $0.projectIds.contains(projectId) }
    }

    /// 프로젝트와 그 소속 워크스페이스 — 분리 창 뷰가 스토어(`store(for:in:)`)를 얻으려면 둘 다 필요하다.
    func located(_ projectId: String) -> (workspace: Workspace, project: Project)? {
        for ws in workspaces {
            if let project = ws.projects.first(where: { $0.id == projectId }) { return (ws, project) }
        }
        return nil
    }

    /// 그 창의 단축키(⌘T/⌘D/⌘W/⌘F)가 향할 스토어 — 각 창은 **자기 활성 프로젝트**만 조작한다.
    /// 분리 창은 자기 프로젝트를 이미 그리고 있으므로 스토어가 존재한다 —
    /// 없으면(아직 안 열림) 만들지 않는다(생성 = PTY 스폰이라 키 라우팅이 할 일이 아니다).
    func store(ownedBy windowId: WindowID) -> TerminalStore? {
        guard !windowId.isMain else { return mainStore }
        guard let window = projectWindows.first(where: { $0.id == windowId }),
              let projectId = window.activeProjectId else { return nil }
        return existingStore(projectId)
    }

    /// 지금 어느 창에서든 보이고 있는 활성 프로젝트들 — 배지 판정의 입력(보고 있으면 배지를 달지 않는다).
    var visibleActiveProjectIds: Set<String> {
        WindowLayout.visibleActiveProjects(mainActive: activeProject?.id, in: projectWindows)
    }

    // MARK: 라우팅 (§5.3 — early-return이 아니라 **선택자**다)

    /// 활성 좌표를 **어느 창에** 반영할지만 고른다.
    ///
    /// 배지 해제·탭 선택은 호출자가 **이미** 끝냈다 — 여기서 갈라져도 "주의를 요구한 탭"은 이미 선택된 뒤다.
    /// (이 함수를 진입부 early-return으로 쓰면 정작 그 탭이 선택되지 않는다.)
    /// - Returns: true = 분리 창이 좌표를 받았다(메인은 건드리지 않는다) · false = 호출자가 메인 좌표를 바꾼다.
    func routeToOwner(_ projectId: String) -> Bool {
        guard let window = window(owning: projectId) else { return false }
        guard windowHost?.raise(window.id) == true else {
            // 모델엔 있는데 실물 창이 없다 — 도달 불가 프로젝트를 만들지 않도록 메인으로 되돌린다(self-heal).
            moveProjects([projectId], to: .main)
            return false
        }
        clearBadge(projectId) // 그 창을 앞으로 올렸으니 사용자가 보게 된다
        setActiveProject(projectId, inWindow: window.id)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// 분리 창의 활성 프로젝트를 바꾼다(그 창이 품은 프로젝트일 때만).
    func setActiveProject(_ projectId: String, inWindow id: WindowID) {
        updateWindow(id) { window in
            guard window.projectIds.contains(projectId) else { return window }
            var next = window
            next.activeProjectId = projectId
            return next
        }
    }

    // MARK: 이동

    /// 프로젝트들을 대상 창으로 옮긴다. 순서가 곧 안전 규약이다(ARCHITECTURE D28):
    /// 모델 갱신 → 서피스 스탬프 → 활성 좌표 재선택 → 창 reconcile → 저장.
    /// **서피스를 옮기지 않는다** — 소유권만 새기면 뷰 계층이 스스로 재부모화한다.
    func moveProjects(_ ids: [String], to target: WindowID) {
        var next = WindowLayout.move(ids, to: target, in: projectWindows)
        // 대상이 아직 없는 새 창이면 만든다 — move는 창을 만들지 않는다(순수 함수의 책임 밖).
        if !target.isMain, !next.contains(where: { $0.id == target }) {
            next.append(ProjectWindow(id: target, projectIds: ids, activeProjectId: ids.first))
            next = WindowLayout.move(ids, to: target, in: next) // 제거→삽입 재적용(I2: 중복 불가)
        }
        setProjectWindows(WindowLayout.normalize(next, projectIds: allProjectIds))
        for id in ids { stampOwner(id) }
        reselectActiveProjects()
        syncWindows()
        save()
    }

    /// 프로젝트 하나를 새 창으로 분리한다.
    func separateProject(_ projectId: String) {
        guard owner(of: projectId).isMain else { return } // 이미 분리된 건 다시 분리하지 않는다
        moveProjects([projectId], to: WindowID(rawValue: UUID().uuidString))
    }

    /// 워크스페이스의 전 프로젝트를 새 창으로 분리한다 — `moveProjects`의 설탕(D29).
    func separateWorkspace(_ workspaceId: String) {
        guard let ws = workspaces.first(where: { $0.id == workspaceId }), !ws.projects.isEmpty else { return }
        moveProjects(ws.projects.map(\.id), to: WindowID(rawValue: UUID().uuidString))
    }

    /// 분리 창의 프로젝트를 전부 메인으로 되돌린다(창 닫기 = 무손실 재합치기 — D30).
    /// **`closeProject`를 부르지 않는다** — 거기서 서비스·tmux 세션이 죽는다.
    func rejoin(_ windowId: WindowID) {
        guard let window = projectWindows.first(where: { $0.id == windowId }) else { return }
        let returning = window.activeProjectId ?? window.projectIds.first
        moveProjects(window.projectIds, to: .main)
        // 돌아온 프로젝트를 메인이 **실제로 보여준다** — 창만 사라지고 화면이 그대로면
        // 사용자는 방금 닫은 터미널을 잃었다고 생각한다(무손실 재합치기는 눈에도 보여야 한다).
        guard let returning, let ws = located(returning)?.workspace else { return }
        setActiveId(ws.id)
        setActiveProject(returning)
    }

    /// 분리 창의 크롬 상태(패널 토글·폭)를 고친다 — 그 값은 `ProjectWindow`가 소유한다(명세 §6).
    /// 메인 창 것은 `AppState`의 기존 필드(`showExplorer` 등)가 그대로 소유한다.
    func updateWindow(_ id: WindowID, _ transform: (ProjectWindow) -> ProjectWindow) {
        guard let idx = projectWindows.firstIndex(where: { $0.id == id }) else { return }
        var next = projectWindows
        next[idx] = transform(next[idx])
        setProjectWindows(next)
        save()
    }

    /// 분리 창이 움직였다/크기가 바뀌었다 — **메모리엔 즉시, 디스크엔 디바운스**(명세 §10-5).
    /// 드래그 중 매 프레임 `save()`를 부르면 열린 스토어를 전부 재스냅샷하고 JSON을 통째로 쓴다.
    func recordFrame(_ id: WindowID, _ frame: FrameSnapshot) {
        guard let idx = projectWindows.firstIndex(where: { $0.id == id }),
              projectWindows[idx].frame != frame else { return }
        var next = projectWindows
        next[idx].frame = frame
        setProjectWindows(next)
        saveFramesDebounced()
    }

    /// 그 프로젝트를 품은 창을 앞으로 부른다(메인 창의 플레이스홀더·사이드바 클릭에서).
    /// 창이 실물로 없으면(모델만 남은 상태) 메인으로 되돌려 self-heal한다 — 도달 불가 프로젝트를 만들지 않는다.
    ///
    /// 창을 올리는 것만으론 부족하다 — 분리 창은 자기 `activeProjectId` 하나만 그리므로, 그 값을 바꾸지
    /// 않으면 프로젝트가 둘 이상인 창에서 **클릭한 프로젝트가 어느 창에도 안 보인다**(메인은 소유권 가드로
    /// 안 그리고, 그 창은 다른 프로젝트를 그린다).
    func focusWindow(owning projectId: String) {
        guard let window = window(owning: projectId) else { return }
        guard windowHost?.raise(window.id) == true else {
            moveProjects([projectId], to: .main)
            return
        }
        setActiveProject(projectId, inWindow: window.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 반영 (스탬프 · 재선택 · reconcile)

    /// 프로젝트의 스토어·서피스에 현재 소유 창을 새긴다. 포커스 칸의 탭만 새 창에서 키를 받는다(원샷).
    /// 아직 안 연 프로젝트는 할 일이 없다 — `store(for:in:)`이 생성 시점에 같은 값을 찍는다.
    func stampOwner(_ projectId: String) {
        guard let store = existingStore(projectId) else { return }
        let focused = store.controller.focusedPaneId
            .flatMap { store.controller.selectedTab(inPane: $0)?.id }
        store.setOwnerWindow(owner(of: projectId), focusedTab: focused)
    }

    /// 창이 바뀐 뒤 각 창의 활성 프로젝트를 다시 고른다.
    /// 분리 창 쪽은 `normalize`가 이미 clamp했고, 여기서는 **메인 좌표**만 고친다 —
    /// 메인의 활성 프로젝트가 분리돼 나갔으면 그 워크스페이스에 남은(메인 소유) 첫 프로젝트로 옮긴다.
    /// 남은 게 없으면 그대로 둔다 — 뷰가 "다른 창에서 열림" 플레이스홀더를 그린다(파괴는 좁게).
    func reselectActiveProjects() {
        for ws in workspaces {
            guard !owner(of: ws.activeProjectId).isMain,
                  let fallback = ws.projects.first(where: { owner(of: $0.id).isMain }) else { continue }
            setActiveProject(fallback.id, inWorkspace: ws.id)
        }
    }

    /// 모델(`projectWindows`) ⇄ 실물(`NSWindow`) reconcile — 모델에 있는데 창이 없으면 열고, 반대면 닫는다(I4).
    /// `projectWindows`를 바꾸는 **모든** 경로가 여기를 통과한다 → 유령 창·도달 불가 프로젝트가 생길 수 없다.
    func syncWindows() { windowHost?.sync(projectWindows) }
}
