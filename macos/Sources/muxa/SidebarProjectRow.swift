import SwiftUI

/// 프로젝트 행 = 트리의 **주인공**. 폴더가 아니라 "그 안의 에이전트가 지금 뭘 하고 있나"를 말한다.
///
/// 선택 표시는 브랜드색 wash가 아니라 **중립 채움**(btnActive) — 크롬은 무채, 색은 신호다.
/// 워크트리 프로젝트(path != nil)의 이름은 모노스페이스다(브랜치는 식별자다).
struct SidebarProjectRow: View {
    let state: AppState
    let workspace: Workspace
    let project: Project
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?


    /// 다른 창이 그리고 있는 프로젝트 — 메인의 활성 표시(채움)를 주지 않는다(여긴 그 프로젝트가 없다).
    private var separated: Bool { !state.owner(of: project.id).isMain }
    private var active: Bool {
        project.id == workspace.activeProjectId && workspace.id == state.activeId && !separated
    }
    private var hovered: Bool { hoveredId == project.id || menuOpenId == project.id }

    var body: some View {
        let status = state.projectStatus(project.id)
        let services = state.services(of: project.id)
        // 에이전트 큐: 탭 분포(작업중·대기·유휴 몇 탭)를 아이콘+개수로. 조용한 유휴(단일 탭·미개봉)는 1줄.
        let tabs = state.projectTabStatus(project.id)
        let showBreakdown = tabs.working > 0 || tabs.waiting > 0 || tabs.done > 0
            || (tabs.working + tabs.waiting + tabs.done + tabs.idle) > 1
        VStack(alignment: .leading, spacing: Space.tight) {
            topRow(status: status, services: services)
            if showBreakdown { breakdown(tabs) }
        }
        .padding(.leading, Space.treeIndent) // 2단 트리의 들여쓰기 = 위계
        .padding(.trailing, Space.sm)
        .padding(.vertical, showBreakdown ? Space.tight : 0) // 2줄일 때만 위아래 숨을 준다
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: RowHeight.row)
        .background(active ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .sidebarRow(id: project.id, label: displayName, selected: active,
                    hoveredId: $hoveredId, menuOpenId: $menuOpenId, activate: select) {
            ProjectMenu.items(for: project, in: workspace, state: state)
        }
        .help(displayPath(project.path ?? workspace.path, home: SystemPaths.home))
    }

    /// 이름 줄 — 상태 점 · 이름 · (분리 글리프) · 서비스 요약/닫기. 2줄일 땐 이게 위, 상태 라인이 아래.
    private func topRow(status: SidebarTree.ProjectStatus, services: [Service]) -> some View {
        HStack(spacing: Space.sm) {
            // 상태 **아이콘**(점이 아니라 글리프) — 색만이 아니라 모양으로 상태를 말한다. 슬롯을 고정해
            // 아이콘 모양이 상태마다 달라도(링·원·느낌표) 이름의 시작선이 흔들리지 않는다.
            Image(systemName: ProjectStatusStyle.glyph(status))
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(ProjectStatusStyle.color(status))
                .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
            Text(displayName)
                .font(nameFont)
                .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            // 분리된 프로젝트도 **트리에 그대로 남는다** — 숨기면 어디로 갔는지 알 수 없다.
            // 이름 뒤 마이크로 글리프가 "다른 창에 있다"만 말하고, 클릭하면 그 창이 앞으로 온다.
            if separated {
                Image(systemName: "macwindow")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: Space.xs)
            // ✕는 서비스 요약과 **같은 자리**를 쓴다(hover 시 교체 → 행 폭이 흔들리지 않는다).
            // 교체를 `if hovered`(존재)가 아니라 opacity(보임)로 한다 — hover가 없는 사용자에게
            // ✕가 접근성 트리에서 사라지면 "프로젝트 닫기"에 도달할 길이 우클릭 메뉴뿐이고,
            // 그 메뉴도 마우스 전용이다. 마우스 히트만 hover로 가른다(안 보이는 ✕가 눌리지 않게).
            ZStack(alignment: .trailing) {
                if !services.isEmpty {
                    serviceSummary(services)
                        .opacity(hovered ? 0 : 1)
                        .accessibilityHidden(true) // 요약은 행 라벨(이름)에 섞이면 소음이다
                }
                if workspace.projects.count > 1 {
                    closeButton
                        .opacity(hovered ? 1 : 0)
                        .allowsHitTesting(hovered)
                }
            }
        }
        .frame(height: RowHeight.row)
    }

    /// 2번째 줄 = **상태별 탭 분포**를 아이콘 + 개수로(긴급도순, 0인 상태는 생략).
    /// 색·글리프·라벨은 `StatusStyle`(SSOT) — 톤으로 직접 그린다. **done은 유휴에 접지 않고 success(초록 체크)로**
    /// 별도 표기해 패인 테두리의 done 초록과 일치시킨다(C2 — 한 상태, 한 얼굴).
    private func breakdown(_ tabs: (working: Int, waiting: Int, done: Int, idle: Int)) -> some View {
        // **긴급도순**: 대기 → 작업중 → 완료 → 유휴. 왼쪽 끝만 훑으면 "나를 기다리나"가 판정된다.
        HStack(spacing: Space.md) {
            if tabs.waiting > 0 { tabStat(.attention, tabs.waiting, jump: [.waiting]) }
            if tabs.working > 0 { tabStat(.active, tabs.working, jump: [.working]) }
            if tabs.done > 0 { tabStat(.success, tabs.done, jump: [.done]) }
            if tabs.idle > 0 { tabStat(.quiet, tabs.idle, jump: [.idle]) }
        }
        .padding(.leading, IconSize.statusGlyph + Space.sm) // 이름 아래에 정렬(상태 아이콘 슬롯 + 간격)
    }

    /// 톤 하나의 아이콘 + 탭 개수 — 색·글리프·라벨은 `StatusStyle`(SSOT)이 정한다(색+모양 둘 다, 색맹 안전).
    /// **클릭 = 그 상태의 다음 탭으로 순환 점프**(`jumpToProjectTab`). 히트 영역은 글리프+숫자 전체.
    private func tabStat(_ tone: StatusTone, _ count: Int, jump states: Set<AgentActivity>) -> some View {
        let label = StatusStyle.label(tone)
        return Button { state.jumpToProjectTab(project.id, matching: states) } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: StatusStyle.glyph(tone))
                    .font(.muxa(.micro, weight: .semibold))
                Text("\(count)")
                    .font(.muxaMono(.caption))
            }
            .foregroundStyle(StatusStyle.color(tone))
            .contentShape(Rectangle()) // 글리프 사이 여백도 눌리게(작은 타깃 보정)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("\(label) 탭 \(count)개 — 클릭해 이동")
        .accessibilityLabel("\(project.name) \(label) 탭 \(count)개로 이동")
    }

    /// 행 클릭 = 이 프로젝트로 이동(마우스·VoiceOver가 같은 동작을 쓴다).
    private func select() {
        // 분리된 프로젝트는 그 창을 앞으로 부르기만 한다 — 메인의 활성 좌표는 건드리지 않는다
        // (메인이 그 프로젝트를 그리지 않으므로 활성으로 바꾸면 플레이스홀더만 남는다).
        if separated {
            state.focusWindow(owning: project.id)
            return
        }
        // 배지(주의) 있는 프로젝트로 이동하면 Git 패널까지 함께 연다(원클릭 검토 동선).
        if state.badgedProjects.contains(project.id) {
            state.revealActivity(projectId: project.id)
        } else {
            // **setActiveId 먼저** — setActiveProject는 활성 워크스페이스 대상이라,
            // 다른 그룹의 프로젝트를 눌렀을 때 전환 없이 부르면 조용히 씹힌다.
            state.setActiveId(workspace.id)
            state.setActiveProject(project.id)
        }
    }

    /// 표시 이름 = **사용자가 붙인 프로젝트 이름**(예: "메인"). 브레드크럼과 한 규칙 — 사이드바·상단바가
    /// 같은 것을 말한다. 브랜치는 Git 패널이 보여준다(여기서 브랜치를 조회하지 않는다).
    private var displayName: String { project.name }

    /// 워크트리 이름은 **식별자**(=브랜치)라 모노스페이스로 읽는다(브레드크럼·이름 칩과 같은 규칙).
    private var nameFont: Font {
        let weight: Font.Weight = active ? .medium : .regular
        return project.usesMonoName ? .muxaMono(.body, weight: weight) : .muxa(.body, weight: weight)
    }

    /// 서비스 요약 — 색·글리프 규칙은 `ServiceStatusStyle` 재사용(새 규칙을 만들지 않는다).
    private func serviceSummary(_ services: [Service]) -> some View {
        let summary = ServiceStatusStyle.summarize(state.serviceStatuses(of: project.id))
        return HStack(spacing: Space.tight) {
            Image(systemName: ServiceStatusStyle.glyph(summary)).font(.muxa(.micro))
            Text("\(services.count)").font(.muxaMono(.caption))
        }
        .foregroundStyle(ServiceStatusStyle.color(summary))
    }

    private var closeButton: some View {
        Button { ProjectClose.request(project, state: state) } label: {
            Image(systemName: "xmark")
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("프로젝트 닫기")
        // 파괴적 동작인데 대상이 안 들리면 안 된다 — VO는 `.help()`를 hint로만 읽는다(라벨은 "xmark"로 떨어진다).
        .accessibilityLabel("\(project.name) 닫기")
    }
}
