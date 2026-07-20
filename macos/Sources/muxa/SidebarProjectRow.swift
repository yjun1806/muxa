import Bonsplit
import SwiftUI

/// 프로젝트 행 = 트리의 **주인공**. 폴더가 아니라 "그 안의 에이전트가 지금 뭘 하고 있나"를 말한다.
/// v2 시안: 프로젝트들은 **레인**(옅은 면, `SidebarSUI`) 위에 앉는다 — 들여쓰기·가이드선 없이 면이 소속을 그린다.
///
/// 선택 표시는 브랜드색 wash가 아니라 **중립 채움**(btnActive) — 크롬은 무채, 색은 신호다.
/// 워크트리 프로젝트(path != nil)의 이름은 모노스페이스다(브랜치는 식별자다).
///
/// **상태는 두 축으로 나뉜다**(Orca 본받아 축소): 에이전트 축(작업중·주의·유휴+완료)은 **롤업 점 하나**
/// (`projectLeadingTone` — 가장 센 신호)로 요약하고, 상세는 셰브론으로 펼치는 에이전트 목록이 맡는다.
/// **롤업은 점, 살아있는 글리프(스피너·펄스)는 펼친 에이전트 행만** — 개요와 실체를 모양으로도 가른다(v2).
/// 실패(빨강)는 에이전트가 아니라 **서비스 죽음**에만 뜬다(`hasDeadService` → 서비스 요약이 맡는다).
struct SidebarProjectRow: View {
    let state: AppState
    let workspace: Workspace
    let project: Project
    @Binding var hoveredId: String?
    @Binding var menuOpenId: String?
    /// 에이전트 목록 펼침 여부 — AppState 소유(영속). 기본 펼침, **접은 것만** 기억한다
    /// (행 로컬 @State였을 땐 재시작·뷰 재생성마다 접혀 시작해 매번 다시 펼쳐야 했다).
    private var expanded: Bool { state.isAgentListExpanded(project.id) }

    /// 다른 창이 그리고 있는 프로젝트 — 메인의 활성 표시(채움)를 주지 않는다(여긴 그 프로젝트가 없다).
    private var separated: Bool { !state.owner(of: project.id).isMain }
    private var active: Bool {
        project.id == workspace.activeProjectId && workspace.id == state.activeId && !separated
    }
    private var hovered: Bool { hoveredId == project.id || menuOpenId == project.id }
    /// 이 프로젝트의 워크트리 폴더가 디스크에서 사라졌나(닫지 않고 배지로만 표시 — D31).
    private var worktreeGone: Bool { state.deadWorktreeProjectIds.contains(project.id) }
    /// 펼칠 값이 있나 — 신호(작업중·대기·완료)가 있거나 탭이 여럿(뷰어 포함)이면. 유휴 1개뿐이면 접어 둔다.
    private var expandable: Bool {
        let s = state.projectTabStatus(project.id)
        return (s.working + s.waiting + s.done > 0) || (s.working + s.waiting + s.done + s.idle) > 1
    }

    var body: some View {
        let leadingTone = state.projectLeadingTone(project.id)
        let services = state.services(of: project.id)
        VStack(alignment: .leading, spacing: Space.tight) {
            // 채움(active·hover)은 **이름 줄에만** — 블록 전체에 걸면 에이전트 행의 hover·선택 채움이
            // 같은 색 위에 그려져 안 보인다(L1 행 문법이 죽는다). 에이전트 행은 레인 위에 직접 앉는다.
            // 패딩은 채움 **안쪽**(내용 인셋)이다 — 채움 밖에 두면 dot·✕가 채움 모서리에 딱 붙어 어색하다.
            // leading xs = 레인 인셋과 합쳐 이름 시작선이 워크스페이스 헤더와 한 세로선(레인 4+행 4+슬롯 11+간격 6
            // = 헤더 6+글리프 13+간격 6 = 25). trailing은 sm — ✕·셰브론이 모서리에서 숨 쉴 자리.
            topRow(leadingTone: leadingTone, services: services, expandable: expandable)
                .padding(.leading, Space.xs)
                .padding(.trailing, Space.sm)
                .background(active ? Color.pBtnActive : (hovered ? Color.pBtnHover : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            if expandable && expanded {
                agentList()
            }
        }
        .padding(.vertical, (expandable && expanded) ? Space.tight : 0) // 2줄일 때만 위아래 숨을 준다
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: RowHeight.row)
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .sidebarRow(id: project.id, label: displayName, selected: active,
                    hoveredId: $hoveredId, menuOpenId: $menuOpenId, activate: activate) {
            ProjectMenu.items(for: project, in: workspace, state: state)
        }
        .help(displayPath(project.path ?? workspace.path, home: SystemPaths.home))
    }

    /// 이름 줄 — **리딩 롤업 점**(가장 센 신호 하나) · 이름 · (분리 글리프) · 서비스 요약/닫기 · 펼침 셰브론.
    private func topRow(leadingTone: StatusTone, services: [Service], expandable: Bool) -> some View {
        HStack(spacing: Space.sm) {
            // 리딩 = 프로젝트 롤업(가장 센 신호 하나 — 죽은 서비스 빨강 · 대기 로즈 · 작업중 인디고)을 **점**으로.
            // 유휴는 **작은 무채 점**(빈 슬롯은 행이 텅 비어 오류 같았다). 상세는 셰브론/제목으로 펼치는 목록이 맡는다.
            rollupDot(leadingTone)
            Text(displayName)
                .font(nameFont)
                .foregroundStyle(active || hovered ? Color.pFg : Color.pMuted)
                .strikethrough(worktreeGone, color: Color.pMuted) // 폴더 사라짐 = "묘비"(상태색 안 빌리고 취소선으로)
                .lineLimit(1)
                .truncationMode(.tail)
            // 열린 탭 개수 배지 — 워크스페이스 헤더(프로젝트 수)와 같은 문법. 안 연 프로젝트는
            // 복원 스냅샷을 세고(`projectTabCount`), 탭이 없으면 숨긴다(0은 소음).
            let tabCount = state.projectTabCount(project.id)
            if tabCount > 0 {
                CountBadge(count: tabCount)
                    .accessibilityLabel("열린 탭 \(tabCount)개")
            }
            // 워크트리 폴더가 사라진 프로젝트 — 닫지 않고 표시만(사용자가 정리). 서비스-빨강·에이전트-앰버와
            // 헷갈리지 않게 무채 글리프 + 취소선으로 조용히 알린다.
            if worktreeGone {
                // questionmark.folder = "참조 유실"(Xcode missing reference 관례). badge.minus 계열은
                // "제거하는 동작"으로 읽혀 누르면 지워질 것 같은 오독 여지가 있었다(디자인 리뷰).
                Image(systemName: "questionmark.folder")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                    .help("워크트리 폴더가 사라졌습니다 — 정리하려면 프로젝트를 닫으세요")
                    .accessibilityLabel("\(project.name) 워크트리 폴더 사라짐")
            }
            // 분리된 프로젝트도 **트리에 그대로 남는다** — 숨기면 어디로 갔는지 알 수 없다.
            if separated {
                Image(systemName: "macwindow")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: Space.xs)
            // ✕는 **열려 있는 터미널이 하나도 없을 때만** 노출한다 — 터미널이 살아 있으면 실수 클릭
            // 한 번이 모든 세션을 죽인다(닫기의 정식 경로는 우클릭 메뉴 → 확인 시트).
            // 뜰 때는 서비스 요약과 **같은 자리**(hover 시 교체 → 행 폭 불변). 교체는 존재가 아니라 opacity로
            // (hover 없는 사용자의 접근성 트리에서 ✕가 사라지지 않게). 마우스 히트만 hover로 가른다.
            let showsClose = workspace.projects.count > 1 && !state.hasOpenTerminals(project.id)
            ZStack(alignment: .trailing) {
                if !services.isEmpty {
                    serviceSummary(services)
                        .opacity(hovered && showsClose ? 0 : 1) // ✕가 없으면 hover에도 요약을 유지한다
                        .accessibilityHidden(true) // 요약은 행 라벨(이름)에 섞이면 소음이다
                }
                if showsClose {
                    closeButton
                        .opacity(hovered ? 1 : 0)
                        .allowsHitTesting(hovered)
                }
            }
            // 펼침 셰브론 — 펼칠 값이 있을 때만. hover에서 보이고(펼쳐져 있으면 옅게 유지),
            // 클릭=목록 토글(행 클릭 전환보다 먼저 자기 히트를 가져간다). 워크스페이스 헤더와 같은 문법(▼→▶).
            if expandable { expandToggle }
        }
        .frame(height: RowHeight.row)
    }

    /// 목록 펼침/접힘 셰브론 — hover에서만 보인다(보임은 opacity, 히트는 hover가 가른다).
    private var expandToggle: some View {
        Button { state.toggleAgentList(project.id) } label: {
            Image(systemName: "chevron.down")
                .font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
                .rotationEffect(.degrees(expanded ? 0 : -90))
                .animation(Motion.fast, value: expanded)
                .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : (expanded ? 0.7 : 0))
        .allowsHitTesting(hovered)
        .clickCursor()
        .help(expanded ? "에이전트 목록 접기" : "에이전트 목록 펼치기")
        .accessibilityLabel(expanded ? "에이전트 목록 접기" : "에이전트 목록 펼치기")
    }

    // MARK: 에이전트 목록 — 펼쳤을 때 탭별 상세(L1 — 풀폭 목록 행)

    /// 펼침 목록 = **터미널 덩어리**(긴급도순 + "유휴 N" 접기) · 구분선 · **뷰어 덩어리**.
    /// 행은 **프로젝트 행과 같은 문법**(풀폭·hover 채움·radius)을 쓴다 — "클릭 가능한 목록"으로 읽히게(L1).
    ///
    /// 두 덩어리를 가르는 이유: 터미널은 **지켜보는 것**(상태가 변한다)이고 뷰어는 **참고하는 것**
    /// (가만히 있다)이다. 섞이면 실행 중인 것을 훑을 때마다 정적인 파일 이름을 건너뛰게 된다.
    /// 나누는 판정은 순수 함수가 맡는다(`AgentRow.sections` — 빈 그룹 처리까지 테스트로 못 박혀 있다).
    @ViewBuilder
    private func agentList() -> some View {
        let sections = AgentRow.sections(state.agentRows(project.id))
        // "지금 보고 있는 탭"(활성 프로젝트의 포커스 칸 선택 탭)은 선택 채움 — 목록에서도 현재 위치가 보인다.
        let selected = active ? state.selectedTabId(project.id) : nil
        VStack(alignment: .leading, spacing: Space.tight) {
            ForEach(sections.terminals) { agentRowView($0, selected: selected) }
            // 유휴 폴드는 **선 위**(터미널 쪽)에 남는다 — 아래로 내려가면 뷰어를 접는다는 오해를 준다.
            if sections.idleTerminals > 0 { idleFold(sections.idleTerminals) }
            if sections.showsSeparator { sectionSeparator }
            ForEach(sections.viewers) { agentRowView($0, selected: selected) }
        }
        .padding(.top, Space.tight)
    }

    /// 터미널 ↔ 뷰어 경계 — **목록 폭에만** 걸리는 1pt 선.
    ///
    /// 사이드바는 원래 가로선을 쓰지 않는다(간격이 위계). 그래서 이 선은 레인을 가로지르지 않고
    /// 행 내용과 같은 들여쓰기 안에 갇힌다 — 전폭으로 늘리면 상위 경계(프로젝트 사이)보다 세 보여
    /// 트리에서 **가장 깊은 경계만 가장 강한** 위계 역전이 생긴다.
    private var sectionSeparator: some View {
        Rectangle()
            .fill(Color.pBorder)
            .frame(height: RowHeight.hairline)
            .padding(.leading, agentIndent)
            .padding(.trailing, Space.sm)
            .padding(.vertical, Space.xs) // 선이 행에 달라붙지 않게 — 위아래로 숨을 준다
            .accessibilityHidden(true) // 장식이다. 순서(터미널 먼저)가 이미 그룹을 말한다
    }

    /// 에이전트 한 행 — **프롬프트가 있으면 2줄**(제목=마지막 프롬프트, 아랫줄=탭 이름–상태/라이브 도구),
    /// 없으면 현행 1줄(제목 – 본문). 우측 열은 그룹=서브탭 개수 · 대기=경과.
    /// **클릭 = 그 탭 지목 이동**(`focusAgentTab`, 상태 순환이 아니라 이 탭 하나).
    /// 프롬프트 행의 hover는 카드(전문+이미지)가, 나머지는 툴팁이 말한다 — 둘을 겹치지 않는다.
    @ViewBuilder
    private func agentRowView(_ r: AgentRow, selected: TabID?) -> some View {
        let desc = rowDescription(r)
        let button = Button { state.focusAgentTab(project.id, r.tabId) } label: {
            rowContent(r)
                .padding(.leading, agentIndent)
                .padding(.trailing, Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ListRowFill(selected: r.tabId == selected))
        .clickCursor()
        .accessibilityLabel("\(desc) 탭으로 이동")
        if let prompt = r.prompt, r.promptTitle != nil {
            button.muxaHoverCard(key: "\(r.tabId)#\(prompt.text)#\(prompt.imageCount)") {
                PromptHoverCard(text: prompt.text, imageCount: prompt.imageCount,
                                transcriptPath: state.agentTranscript(project.id, r.tabId))
            }
        } else {
            button.help("\(desc). 클릭해 이동")
        }
    }

    /// 행 본문 — 프롬프트 승격(2줄) 또는 현행(1줄).
    @ViewBuilder
    private func rowContent(_ r: AgentRow) -> some View {
        if let promptTitle = r.promptTitle {
            // **프롬프트가 곧 행의 이름**(일감 목록으로 읽히게) — 아랫줄이 "누가·지금 뭘"을 말한다.
            VStack(alignment: .leading, spacing: Space.tight) {
                HStack(spacing: Space.xs) {
                    statusGlyph(r.state.tone)
                    typeMark(r)
                    Text(promptTitle).font(.muxa(.label)).foregroundStyle(Color.pFg)
                        .lineLimit(1).truncationMode(.tail)
                    if let prompt = r.prompt, prompt.imageCount > 0 { PromptImageChip(count: prompt.imageCount) }
                    Spacer(minLength: 0)
                    if let time = r.timeLabel {
                        Text(time).font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
                    }
                }
                // 아랫줄 — 탭 이름 – 상태/라이브 도구. 제목 시작선(글리프 2슬롯 + 간격)에 맞춘다.
                Text("\(r.title) – \(r.bodyLabel)")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.leading, IconSize.statusGlyph * 2 + Space.xs * 2)
            }
            .padding(.vertical, Space.xs)
        } else {
            HStack(spacing: Space.xs) {
                statusGlyph(r.state.tone) // 유휴(뷰어 등)면 작은 무채 점
                typeMark(r) // Claude 세션이면 마크, 아니면 슬롯 고정(제목 시작선 불변)
                Text(r.title).font(.muxa(.label)).foregroundStyle(Color.pFg)
                    .lineLimit(1).truncationMode(.tail)
                if r.viewerKind == nil { // 그룹 행은 제목 = 종류라 본문이 같은 말의 반복이 된다
                    Text("– \(r.bodyLabel)").font(.muxa(.label)).foregroundStyle(Color.pMuted)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if let count = r.subtabCount {
                    Text("\(count)").font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
                } else if let time = r.timeLabel {
                    Text(time).font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
                }
            }
            .frame(height: RowHeight.tight)
        }
    }

    /// 행 설명(툴팁·VoiceOver) — 프롬프트 행은 프롬프트가 앞장선다.
    private func rowDescription(_ r: AgentRow) -> String {
        if let promptTitle = r.promptTitle { return "\(promptTitle) — \(r.title), \(r.subtitle)" }
        return r.viewerKind == nil ? "\(r.title) — \(r.subtitle)"
                                   : r.subtabCount.map { "\(r.title) \($0)개" } ?? r.title
    }

    /// 타입 마크 — **"이게 뭔가(WHO/무엇)"를 상태 점(WHAT)과 분리해 말한다**(Orca 원칙).
    /// Claude 세션(hooked)이면 공식 Claude 마크(원본 주황 유지), 아니면 탭 종류 아이콘
    /// (터미널·문서·코드·변경…)을 무채로. 슬롯 폭은 고정이라 제목 시작선이 안 흔들린다.
    @ViewBuilder
    private func typeMark(_ r: AgentRow) -> some View {
        if r.isAgent {
            ClaudeMark(size: IconSize.statusGlyph)
        } else {
            Image(systemName: r.typeIcon)
                .font(.muxa(.micro))
                .foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
        }
    }

    /// 유휴 접기 행 — "유휴 N". 클릭=유휴 탭 순환 점프(펼쳐도 개별 나열은 안 함, 소음이라).
    private func idleFold(_ count: Int) -> some View {
        Button { state.jumpToProjectTab(project.id, matching: [.idle]) } label: {
            HStack(spacing: Space.xs) {
                statusGlyph(.quiet) // 작은 무채 점(유휴 — 조용하지만 비어 있진 않다)
                // 접힌 것은 곧 유휴 **터미널**들 — 뷰어 행이 타입 아이콘을 달았는데 이 행만 비면
                // WHO 열이 끊긴다(터미널만 아이콘이 없냐는 인상).
                Image(systemName: "terminal")
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
                Text("유휴 \(count)").font(.muxa(.label)).foregroundStyle(Color.pMuted)
                Spacer(minLength: 0)
            }
            .padding(.leading, agentIndent)
            .padding(.trailing, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: RowHeight.tight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ListRowFill())
        .clickCursor()
        .help("유휴 탭 \(count)개 — 클릭해 이동")
        .accessibilityLabel("\(project.name) 유휴 탭 \(count)개로 이동")
    }

    /// 에이전트 행 내용의 들여쓰기 — 행의 상태 글리프가 프로젝트 **이름** 시작선(위 25pt 리듬)에 온다
    /// (채움은 풀폭, 내용만 들어간다 — 들여쓰기를 행 밖에 주면 hover 채움이 좁아진다).
    private var agentIndent: CGFloat { Space.xs + IconSize.statusGlyph + Space.sm }

    /// 프로젝트 롤업 점 — 색·크기는 `StatusStyle`(SSOT). **유휴도 작은 무채 점**(빈 슬롯은 아이콘이
    /// 하나도 없는 행을 텅 비어 보이게 해 오류 같았다 — 크기·색이 "조용함"을 말한다, 색맹 안전은 크기가).
    /// 살아있는 글리프(스피너·펄스)는 에이전트 행(`StatusMark`)만 쓴다 — 개요(점)와 실체(글리프)의 위계.
    private func rollupDot(_ tone: StatusTone) -> some View {
        Circle()
            .fill(StatusStyle.color(tone))
            .frame(width: StatusStyle.dotSize(tone), height: StatusStyle.dotSize(tone))
            .frame(width: IconSize.statusGlyph, height: IconSize.statusGlyph)
    }

    /// 상태 글리프 슬롯 — `StatusMark`에 위임한다(작업중=스피너·대기=펄스·완료=체크, 유휴=작은 무채 점).
    /// 슬롯 폭 고정으로 이름 시작선이 안 흔들린다.
    private func statusGlyph(_ tone: StatusTone) -> some View {
        StatusMark(tone: tone, size: IconSize.statusGlyph)
    }

    /// 행/제목 클릭. **전환과 접힘이 안 겹치게** 한다:
    /// - 다른 프로젝트로 **전환**하면 선택 + 펼침(절대 접지 않는다 — 전환하며 닫히면 성가시다).
    /// - **이미 활성**인 프로젝트를 다시 누르면 펼침/접힘 토글(그때만 접을 수 있다. 셰브론도 언제든 토글).
    private func activate() {
        if active {
            if expandable { state.toggleAgentList(project.id) }
        } else {
            select()
            if expandable { state.expandAgentList(project.id) }
        }
    }

    /// 이 프로젝트로 이동(마우스·VoiceOver가 같은 동작을 쓴다).
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
