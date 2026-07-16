import SwiftUI

/// 프로젝트 행 = 트리의 **주인공**. 폴더가 아니라 "그 안의 에이전트가 지금 뭘 하고 있나"를 말한다.
///
/// 선택 표시는 브랜드색 wash가 아니라 **중립 채움**(btnActive) — 크롬은 무채, 색은 신호다.
/// 워크트리 프로젝트(path != nil)의 이름은 모노스페이스다(브랜치는 식별자다).
///
/// **상태는 두 축으로 나뉜다**(Orca 본받아 축소): 에이전트 축(작업중·주의·유휴+완료)은 **롤업 점 하나**
/// (`projectLeadingTone` — 가장 센 신호)로 요약하고, 상세는 셰브론으로 펼치는 에이전트 목록이 맡는다.
/// 예전의 4-way 분포 pill(작업중·대기·완료·유휴 칩을 한 줄에)은 폐기했다 — 한 행에 네 색을 다는 게 소음이었다.
/// 실패(빨강)는 에이전트가 아니라 **서비스 죽음**에만 뜬다(`hasDeadService` → 서비스 요약이 맡는다).
struct SidebarProjectRow: View {
    let state: AppState
    let workspace: Workspace
    let project: Project
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?
    /// 에이전트 목록 펼침 여부(행 로컬) — 기본 접힘.
    @State private var expanded = false

    /// 다른 창이 그리고 있는 프로젝트 — 메인의 활성 표시(채움)를 주지 않는다(여긴 그 프로젝트가 없다).
    private var separated: Bool { !state.owner(of: project.id).isMain }
    private var active: Bool {
        project.id == workspace.activeProjectId && workspace.id == state.activeId && !separated
    }
    private var hovered: Bool { hoveredId == project.id || menuOpenId == project.id }

    var body: some View {
        let leadingTone = state.projectLeadingTone(project.id)
        let services = state.services(of: project.id)
        let s = state.projectTabStatus(project.id)
        let total = s.working + s.waiting + s.done + s.idle
        // 펼칠 값이 있나 — 신호(작업중·대기·완료)가 있거나 탭이 여럿이면. 유휴 1개뿐이면 접어 둔다.
        let expandable = (s.working + s.waiting + s.done > 0) || total > 1
        VStack(alignment: .leading, spacing: Space.tight) {
            topRow(leadingTone: leadingTone, services: services, expandable: expandable)
            if expandable && expanded {
                agentList().padding(.leading, IconSize.statusGlyph + Space.sm) // 이름 아래 정렬
            }
        }
        .padding(.leading, Space.treeIndent) // 2단 트리의 들여쓰기 = 위계
        .padding(.trailing, Space.sm)
        .padding(.vertical, (expandable && expanded) ? Space.tight : 0) // 2줄일 때만 위아래 숨을 준다
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: RowHeight.row)
        .background(active ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .sidebarRow(id: project.id, label: displayName, selected: active,
                    hoveredId: $hoveredId, menuOpenId: $menuOpenId, activate: select) {
            ProjectMenu.items(for: project, in: workspace, state: state)
        }
        .help(displayPath(project.path ?? workspace.path, home: SystemPaths.home))
    }

    /// 이름 줄 — **리딩 롤업 점**(가장 센 신호 하나) · 이름 · (분리 글리프) · 서비스 요약/닫기 · 펼침 셰브론.
    private func topRow(leadingTone: StatusTone, services: [Service], expandable: Bool) -> some View {
        HStack(spacing: Space.sm) {
            // 리딩 = 프로젝트 롤업(가장 센 신호 하나 — 죽은 서비스 빨강 ⚠ · 대기 호박 … · 작업중 틸 ●).
            // 상세는 셰브론으로 펼치는 목록이 맡는다. 슬롯 고정으로 이름 시작선이 안 흔들린다.
            Image(systemName: StatusStyle.glyph(leadingTone))
                .font(.muxa(.micro, weight: .semibold))
                .foregroundStyle(StatusStyle.color(leadingTone))
                .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
            Text(displayName)
                .font(nameFont)
                .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            // 분리된 프로젝트도 **트리에 그대로 남는다** — 숨기면 어디로 갔는지 알 수 없다.
            if separated {
                Image(systemName: "macwindow")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: Space.xs)
            // ✕는 서비스 요약과 **같은 자리**(hover 시 교체 → 행 폭 불변). 교체는 존재가 아니라 opacity로
            // (hover 없는 사용자의 접근성 트리에서 ✕가 사라지지 않게). 마우스 히트만 hover로 가른다.
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
            // 펼침 셰브론 — 펼칠 값이 있을 때만. 클릭=목록 토글(행 클릭 전환보다 먼저 자기 히트를 가져간다).
            if expandable { expandToggle }
        }
        .frame(height: RowHeight.row)
    }

    /// 목록 펼침/접힘 셰브론.
    private var expandToggle: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(expanded ? "에이전트 목록 접기" : "에이전트 목록 펼치기")
        .accessibilityLabel(expanded ? "에이전트 목록 접기" : "에이전트 목록 펼치기")
    }

    // MARK: 에이전트 목록 — 펼쳤을 때 탭별 상세(무엇을 하는지 한 줄씩)

    /// 펼침 목록 = 비유휴 에이전트 행(긴급도순, 순수 정렬은 `AppState.agentRows`) + 유휴는 "○ 유휴 N" 한 줄로 접기.
    @ViewBuilder
    private func agentList() -> some View {
        let rows = state.agentRows(project.id)
        let visible = rows.filter { $0.state != .idle } // 유휴는 접어 소음 제거
        let idleCount = rows.count - visible.count
        VStack(alignment: .leading, spacing: Space.tight) {
            ForEach(visible) { agentRowView($0) }
            if idleCount > 0 { idleFold(idleCount) }
        }
        .padding(.top, Space.tight)
    }

    /// 에이전트 한 행 — 상태 글리프 + 제목 + 상태 인지형 본문(대기=경과·작업=라이브도구·완료=완료).
    /// **클릭 = 그 탭 지목 이동**(`focusAgentTab`, 상태 순환이 아니라 이 탭 하나).
    private func agentRowView(_ r: AgentRow) -> some View {
        let tone = r.state.tone
        return Button { state.focusAgentTab(project.id, r.tabId) } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: StatusStyle.glyph(tone)).font(.muxa(.micro, weight: .semibold))
                    .foregroundStyle(StatusStyle.color(tone))
                    .frame(width: IconSize.statusGlyph)
                typeMark(r) // Claude 세션이면 마크, 아니면 슬롯 고정(제목 시작선 불변)
                Text(r.title).font(.muxa(.caption)).foregroundStyle(Color.pFg)
                    .lineLimit(1).truncationMode(.tail)
                Text("·").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Text(r.subtitle).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("\(r.title) — \(r.subtitle). 클릭해 이동")
        .accessibilityLabel("\(r.title) \(r.subtitle) 탭으로 이동")
    }

    /// 타입 마크 — Claude 세션(hooked)이면 공식 Claude 마크, 아니면 **빈 슬롯**(같은 폭)으로 제목 시작선을 맞춘다.
    /// 로고라 톤색으로 물들이지 않는다(`ClaudeMark`가 원본 주황 유지). 비-Claude에 다른 글리프를 안 붙이는 건
    /// "에이전트냐 아니냐"만 마크 유무로 즉독하게 하기 위함(소음 최소).
    @ViewBuilder
    private func typeMark(_ r: AgentRow) -> some View {
        if r.isAgent {
            ClaudeMark(size: IconSize.statusGlyph)
        } else {
            Color.clear.frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
        }
    }

    /// 유휴 접기 행 — "○ 유휴 N". 클릭=유휴 탭 순환 점프(펼쳐도 개별 나열은 안 함, 소음이라).
    private func idleFold(_ count: Int) -> some View {
        Button { state.jumpToProjectTab(project.id, matching: [.idle]) } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: StatusStyle.glyph(.quiet)).font(.muxa(.micro, weight: .semibold))
                    .foregroundStyle(StatusStyle.color(.quiet))
                    .frame(width: IconSize.statusGlyph)
                Text("유휴 \(count)").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("유휴 탭 \(count)개 — 클릭해 이동")
        .accessibilityLabel("\(project.name) 유휴 탭 \(count)개로 이동")
    }

    /// 행 클릭 = 이 프로젝트로 이동(마우스·VoiceOver가 같은 동작을 쓴다).
    private func select() {
        // 분리된 프로젝트는 그 창을 앞으로 부르기만 한다 — 메인의 활성 좌표는 건드리지 않는다
        // (메인이 그 프로젝트를 그리지 않으므로 활성으로 바꾸면 플레이스홀더만 남는다).
        if separated {
            state.focusWindow(owning: project.id)
            return
        }
        // 배지(주의) 있는 프로젝트로 이동 — 대기 탭으로 데려가되 **Git 패널은 강제로 열지 않는다**
        // (이동마다 git이 열리면 성가시다 — 검토는 알림 인박스·시스템 알림 클릭에서 연다).
        if state.badgedProjects.contains(project.id) {
            state.revealActivity(projectId: project.id, openGitPanel: false)
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
    /// **실패(빨강)가 뜨는 유일한 자리** — 서비스가 죽으면 여기가 경고 글리프로 바뀐다(에이전트 축엔 실패 없음).
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
