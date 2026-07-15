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
    /// 분포 pill 펼침 여부(행 로컬) — 기본 접힘. 카테고리 >2일 때만 의미가 있다.
    @State private var pillExpanded = false

    /// 다른 창이 그리고 있는 프로젝트 — 메인의 활성 표시(채움)를 주지 않는다(여긴 그 프로젝트가 없다).
    private var separated: Bool { !state.owner(of: project.id).isMain }
    private var active: Bool {
        project.id == workspace.activeProjectId && workspace.id == state.activeId && !separated
    }
    private var hovered: Bool { hoveredId == project.id || menuOpenId == project.id }

    var body: some View {
        let leadingTone = state.projectLeadingTone(project.id)
        let services = state.services(of: project.id)
        let buckets = pillBuckets(state.projectTabStatus(project.id))
        // 침묵 규칙: 신호(작업중·대기·완료) 하나도 없고 탭도 1개뿐이면 pill 없이 1줄로 가라앉는다.
        let showPill = buckets.contains { $0.tone != .quiet } || buckets.reduce(0) { $0 + $1.count } > 1
        VStack(alignment: .leading, spacing: Space.tight) {
            topRow(leadingTone: leadingTone, services: services)
            if showPill { pill(buckets) }
        }
        .padding(.leading, Space.treeIndent) // 2단 트리의 들여쓰기 = 위계
        .padding(.trailing, Space.sm)
        .padding(.vertical, showPill ? Space.tight : 0) // 2줄일 때만 위아래 숨을 준다
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

    /// 이름 줄 — **리딩 상태 아이콘**(경보 헤드라인) · 이름 · (분리 글리프) · 서비스 요약/닫기.
    private func topRow(leadingTone: StatusTone, services: [Service]) -> some View {
        HStack(spacing: Space.sm) {
            // 리딩 = 프로젝트 경보 헤드라인(가장 센 신호 하나 — 죽은 서비스 빨강 ⚠ · 대기 호박 … · 작업중 틸 ●).
            // 탭별 상세는 아래 분포 pill이 맡아 **겹치지 않는다**. 슬롯 고정으로 이름 시작선이 안 흔들린다.
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
        }
        .frame(height: RowHeight.row)
    }

    // MARK: 분포 pill — 리딩과 안 싸우게 **접힘이 기본**, `+N`이 곧 확장

    private typealias Bucket = (tone: StatusTone, count: Int, jump: Set<AgentActivity>)

    /// 탭 분포를 **긴급도순**(대기→작업중→완료→유휴) 버킷으로. 0인 톤은 뺀다.
    private func pillBuckets(_ t: (working: Int, waiting: Int, done: Int, idle: Int)) -> [Bucket] {
        var b: [Bucket] = []
        if t.waiting > 0 { b.append((.attention, t.waiting, [.waiting])) }
        if t.working > 0 { b.append((.active, t.working, [.working])) }
        if t.done > 0 { b.append((.success, t.done, [.done])) }
        if t.idle > 0 { b.append((.quiet, t.idle, [.idle])) }
        return b
    }

    /// 2번째 줄 = **탭 분포 pill**. 평소엔 접혀 요약만, `+N›`으로 펼친다(리딩 헤드라인과 안 싸우게).
    /// 카테고리 ≤2면 전부 노출·확장 없음(숨길 게 없다). >2면 접힘=앞 2개+`+N›`(나머지 탭 수), 펼침=전부+접기.
    private func pill(_ buckets: [Bucket]) -> some View {
        HStack(spacing: Space.sm) { pillContent(buckets) }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.tight)
            .overlay(Capsule().stroke(Color.pBorder, lineWidth: RowHeight.hairline)) // 어느 행 상태에서도 읽히는 pill 윤곽
            .padding(.leading, IconSize.statusGlyph + Space.sm) // 이름 아래에 정렬
    }

    @ViewBuilder
    private func pillContent(_ buckets: [Bucket]) -> some View {
        if buckets.count <= 2 {
            ForEach(buckets.indices, id: \.self) { chip(buckets[$0], expanded: false) }
        } else if pillExpanded {
            ForEach(buckets.indices, id: \.self) { chip(buckets[$0], expanded: true) }
            pillCollapse
        } else {
            chip(buckets[0], expanded: false)
            chip(buckets[1], expanded: false)
            pillMore(hidden: buckets[2...].reduce(0) { $0 + $1.count })
        }
    }

    /// 톤 하나의 칩 — 접힘: 글리프 + 개수(**>1일 때만**). 펼침: 글리프 + 라벨 + 개수.
    /// **클릭 = 그 상태의 다음 탭으로 순환 점프**(`jumpToProjectTab`).
    private func chip(_ b: Bucket, expanded: Bool) -> some View {
        Button { state.jumpToProjectTab(project.id, matching: b.jump) } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: StatusStyle.glyph(b.tone)).font(.muxa(.micro, weight: .semibold))
                if expanded { Text(StatusStyle.label(b.tone)).font(.muxa(.caption)) }
                if expanded || b.count > 1 { Text("\(b.count)").font(.muxaMono(.caption)) }
            }
            .foregroundStyle(StatusStyle.color(b.tone))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("\(StatusStyle.label(b.tone)) 탭 \(b.count)개 — 클릭해 이동")
        .accessibilityLabel("\(project.name) \(StatusStyle.label(b.tone)) 탭 \(b.count)개로 이동")
    }

    /// `+N›` — 나머지 버킷을 펼친다(오버플로 표시가 곧 확장 버튼 = 요소 하나 절약 + 큰 타깃).
    private func pillMore(hidden: Int) -> some View {
        Button { pillExpanded = true } label: {
            HStack(spacing: 1) {
                Text("+\(hidden)").font(.muxaMono(.caption))
                Image(systemName: "chevron.right").font(.muxa(.micro))
            }
            .foregroundStyle(Color.pMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("나머지 탭 \(hidden)개 — 펼치기")
        .accessibilityLabel("탭 분포 \(hidden)개 더 펼치기")
    }

    /// 접기 셰브론(펼친 pill 끝).
    private var pillCollapse: some View {
        Button { pillExpanded = false } label: {
            Image(systemName: "chevron.down").font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("접기")
        .accessibilityLabel("탭 분포 접기")
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
