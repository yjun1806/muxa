import SwiftUI

/// 푸터의 스크립트 칩 — 등록된 스크립트(끝이 있는 명령)의 실행 진입점 + 실행 상태 요약.
///
/// **등록 0개면 자리도 차지하지 않는다**(DetachedStrip과 같은 근거 — 있을 때만 의미가 있다).
/// ServiceStrip의 "숨기지 않는다" 철학과 일부러 다르다: 서비스 칩은 그 기능의 유일한 상시
/// 발견 지점이지만, 스크립트 등록의 발견성은 상시 진입점(⌘K "스크립트 추가")이 맡고 칩은
/// 등록된 것의 상태만 말한다 — 빈 칩을 상시로 두면 푸터가 소음이 된다.
/// 그래서 추가 시트·원샷 플래그 소비는 항상 렌더되는 StatusBar에 있다(칩은 0개면 사라지니
/// 여기 두면 첫 등록 경로가 막힌다).
///
/// 세 모드(`ScriptChipMode` 순수 판정): **평시** = 개수 칩(클릭 = 팝오버) / **실행 중** =
/// [⟳ 이름 · 경과(클릭 = 탭 포커스) | 팝오버 세그먼트] / **완료 잔류** = ✓ 무채(클릭 = 팝오버) ·
/// ✗ 빨강(클릭 = 잔류 탭 포커스 — 로그가 거기 있다). 잔류는 클릭·새 실행 시작 시 해제된다.
struct ScriptStrip: View {
    let state: AppState
    let project: Project
    /// 실행 레지스트리(`scriptRuns`)의 소유자 — StatusBar가 활성 프로젝트의 스토어를 넘긴다.
    let store: TerminalStore

    @State private var showPopover = false
    @State private var hovered = false
    /// 실행 중 경과("12s") 갱신용 — **칩 로컬 @State**다. StatusBar 레벨에 두면 매초
    /// 푸터 전체가 리렌더된다(tick은 실행 중 모드에만 붙인다).
    @State private var now = Date()

    /// 이름 폭 상한 — 긴 스크립트 이름이 칩 폭을 출렁여 옆 칩(서비스)을 밀지 않게.
    private static let nameMaxWidth: CGFloat = 120

    private var scripts: [Script] { state.scripts(of: project.id) }

    private var mode: ScriptChipMode {
        ScriptChipMode.judge(scriptCount: scripts.count, runs: Array(store.scriptRuns.values))
    }

    var body: some View {
        if mode != .hidden {
            chip
                .muxaPopover(isPresented: $showPopover) {
                    ScriptPopover(state: state, project: project, store: store) { showPopover = false }
                }
        }
    }

    // MARK: 모드별 칩

    @ViewBuilder private var chip: some View {
        switch mode {
        case .hidden:
            EmptyView()
        case .idle(let count):
            idleChip(count: count)
        case .running(let active):
            runningChip(active)
        case .lingering(let run):
            lingerChip(run)
        }
    }

    /// 평시 — 개수만 말하는 조용한 칩. 클릭 = 팝오버(FooterChip이 열림 배경까지 관리).
    private func idleChip(count: Int) -> some View {
        FooterChip(isOpen: $showPopover, help: "스크립트 \(count)개 — 클릭해 실행·추가") {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: TerminalStore.scriptTabIcon)
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                Text("\(count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
            }
        }
        .accessibilityLabel("스크립트 \(count)개")
    }

    /// 실행 중 — 클릭 의미가 "탭 포커스"로 바뀌므로 FooterChip(팝오버 토글 고정)을 못 쓴다.
    /// ServiceStrip의 2세그먼트 문법: [실행 세그먼트 | 세로선 | 팝오버 세그먼트].
    private func runningChip(_ active: [ScriptRun]) -> some View {
        HStack(spacing: 0) {
            runningSegment(active)
            VDivider(height: 12)
            popoverSegment
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.tight)
        .background(Color.footerChip(isOpen: showPopover, hovered: hovered),
                    in: RoundedRectangle(cornerRadius: Radius.sm))
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .tick(every: 1, into: $now) // 경과 초 갱신 — 이 칩 안에서만 리렌더된다
    }

    /// [⟳ (N ·) 최신이름 · 12s] — 클릭하면 최신 실행 탭으로.
    private func runningSegment(_ active: [ScriptRun]) -> some View {
        // judge가 최신 시작 순으로 정렬해 준다 — 첫 번째가 헤드라인.
        let latest = active[0]
        return Button {
            state.focusAgentTab(project.id, latest.tabId)
        } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.glyph(latest.state))
                    .font(.muxa(.micro))
                    .foregroundStyle(ScriptStatusStyle.color(latest.state))
                if active.count > 1 {
                    Text("\(active.count)")
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(Color.pFg)
                    Text("·").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                }
                Text(latest.name)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.nameMaxWidth, alignment: .leading)
                    // maxWidth 단독은 탐욕 확장이라 짧은 이름도 120pt를 다 먹는다 — fixedSize가
                    // 자연 폭을 제안하게 해 frame이 **상한으로만** 동작하게 한다(긴 이름만 잘린다).
                    .fixedSize(horizontal: true, vertical: false)
                if let tail = ScriptStatusStyle.tail(latest, now: now) {
                    Text("· \(tail)")
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(Color.pMuted)
                }
            }
            .padding(.trailing, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(runningHelp(active))
        .accessibilityLabel("스크립트 \(latest.name) \(ScriptStatusStyle.label(latest.state))")
    }

    /// 실행 중 모드의 팝오버 진입 — 상세(여러 실행·다른 스크립트)는 목록이 말한다.
    private var popoverSegment: some View {
        Button { showPopover.toggle() } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: TerminalStore.scriptTabIcon)
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                Text("\(scripts.count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
            }
            .padding(.leading, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("스크립트 목록 — 클릭해 열기")
        .accessibilityLabel("스크립트 목록 열기")
    }

    /// 완료 잔류 — [✓ 이름 8s](무채) / [✗ 이름 exit 2](빨강). 색+글리프 이중 신호(DESIGN §2).
    /// 클릭 = 잔류 해제("확인했다") + 실패는 잔류 탭으로(로그가 거기 있다), 성공·미상은 팝오버.
    private func lingerChip(_ run: ScriptRun) -> some View {
        Button { lingerClicked(run) } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.glyph(run.state))
                    .font(.muxa(.micro))
                    .foregroundStyle(ScriptStatusStyle.color(run.state))
                Text(run.name)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.nameMaxWidth, alignment: .leading)
                    // 상한으로만 동작 — runningSegment의 같은 이유(짧은 이름이 칩을 120pt로 부풀리지 않게).
                    .fixedSize(horizontal: true, vertical: false)
                if let tail = ScriptStatusStyle.tail(run, now: now) {
                    Text(tail)
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(ScriptStatusStyle.color(run.state))
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(Color.footerChip(isOpen: showPopover, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help(lingerHelp(run))
        // 색·글리프는 스크린리더에 없다 — exit code까지 말로 한 번 더(DESIGN §2 규칙).
        .accessibilityLabel("스크립트 \(run.name) \(ScriptStatusStyle.label(run.state))")
    }

    private func lingerClicked(_ run: ScriptRun) {
        store.removeScriptRun(run.scriptId) // 클릭 = 확인 — 잔류를 내린다
        if run.isFailure {
            state.focusAgentTab(project.id, run.tabId) // 실패 탭은 셸로 잔류 — 로그가 거기 있다
        } else {
            showPopover = true // 성공·미상은 탭이 이미 없다 — 목록으로
        }
    }

    // MARK: 문구

    private func runningHelp(_ active: [ScriptRun]) -> String {
        let latest = active[0]
        if active.count > 1 {
            return "스크립트 \(active.count)개 실행 중 (최신: \(latest.name)) — 클릭해 탭 보기"
        }
        return "‘\(latest.name)’ 실행 중 — 클릭해 탭 보기"
    }

    private func lingerHelp(_ run: ScriptRun) -> String {
        run.isFailure
            ? "‘\(run.name)’ \(ScriptStatusStyle.label(run.state)) — 클릭해 로그 보기"
            : "‘\(run.name)’ \(ScriptStatusStyle.label(run.state)) — 클릭해 목록 열기"
    }
}
