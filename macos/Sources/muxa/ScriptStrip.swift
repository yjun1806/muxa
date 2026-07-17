import SwiftUI

/// 푸터의 스크립트 칩 — 등록된 스크립트(끝이 있는 명령)의 실행 진입점 + 실행 상태 요약.
///
/// **등록 0개여도 그린다** — 서비스 칩의 "숨기지 않는다" 철학과 같아졌다: 이 칩이 스크립트
/// 기능의 상시 발견 지점이고, 실행 버튼이 항상 서비스 칩 옆 이 자리에 있다.
/// (추가 시트·원샷 플래그 소비는 여전히 StatusBar에 있다 — 팝오버는 별도 NSWindow라 시트를 못 띄운다.)
///
/// 네 모드(`ScriptChipMode` 순수 판정): **빈 칩** = 플레이스홀더(클릭 = 팝오버 → ＋추가) /
/// **평시** = 개수 칩(클릭 = 팝오버) / **실행 중** = [⟳ 이름 · 경과(클릭 = 도크 출력) | 팝오버 세그먼트] /
/// **완료 잔류** = ✓ 무채 · ✗ 빨강(클릭 = 확인 + 도크 로그 — 종료 로그가 거기 보존돼 있다).
/// 잔류는 클릭·새 실행 시작 시 내려간다(acknowledge — 레지스트리·로그는 남는다).
struct ScriptStrip: View {
    let state: AppState
    let project: Project

    @State private var showPopover = false
    @State private var hovered = false
    /// 실행 중 경과("12s") 갱신용 — **칩 로컬 @State**다. StatusBar 레벨에 두면 매초
    /// 푸터 전체가 리렌더된다(tick은 실행 중 모드에만 붙인다).
    @State private var now = Date()

    /// 이름 폭 상한 — 긴 스크립트 이름이 칩 폭을 출렁여 옆 칩(서비스)을 밀지 않게.
    private static let nameMaxWidth: CGFloat = 120

    private var scripts: [Script] { state.scripts(of: project.id) }

    private var mode: ScriptChipMode {
        ScriptChipMode.judge(scriptCount: scripts.count, runs: state.scriptRuns(of: project.id))
    }

    var body: some View {
        chip
            .muxaPopover(isPresented: $showPopover) {
                ScriptPopover(state: state, project: project) { showPopover = false }
            }
    }

    // MARK: 모드별 칩

    @ViewBuilder private var chip: some View {
        switch mode {
        case .empty:
            placeholder
        case .idle(let count):
            idleChip(count: count)
        case .running(let active):
            runningChip(active)
        case .lingering(let run):
            lingerChip(run)
        }
    }

    /// 등록 0개 — 이름만 말하는 플레이스홀더(ServiceStrip.placeholder와 같은 문법).
    /// 클릭 = 팝오버(빈 목록 + ＋추가) — 첫 등록 경로가 칩에서 바로 열린다.
    private var placeholder: some View {
        FooterChip(isOpen: $showPopover, help: "스크립트 추가 — 빌드·테스트처럼 끝이 있는 명령") {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.icon).font(.muxa(.micro))
                Text("스크립트").font(.muxa(.label))
            }
            .foregroundStyle(Color.pMuted)
        }
        .accessibilityLabel("스크립트 추가")
    }

    /// 평시 — 개수만 말하는 조용한 칩. 클릭 = 팝오버(FooterChip이 열림 배경까지 관리).
    private func idleChip(count: Int) -> some View {
        FooterChip(isOpen: $showPopover, help: "스크립트 \(count)개 — 클릭해 실행·추가") {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.icon)
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                Text("\(count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
            }
        }
        .accessibilityLabel("스크립트 \(count)개")
    }

    /// 실행 중 — 클릭 의미가 "도크에서 출력 보기"로 바뀌므로 FooterChip(팝오버 토글 고정)을 못 쓴다.
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

    /// [⟳ (N ·) 최신이름 · 12s] — 클릭하면 도크가 열려 그 실행의 라이브 출력이 보인다.
    private func runningSegment(_ active: [ScriptRun]) -> some View {
        // judge가 최신 시작 순으로 정렬해 준다 — 첫 번째가 헤드라인.
        let latest = active[0]
        return Button {
            state.revealScript(scriptId: latest.scriptId)
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
                Image(systemName: ScriptStatusStyle.icon)
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
    /// 클릭 = 확인(acknowledge — 칩만 내려간다) + 도크 로그 열기: 성공·실패 모두 종료 로그가
    /// tmux pane에 보존돼 있다(백그라운드 실행이라 화면 어디에도 흔적이 없다 — 여기가 유일한 다리).
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
        state.acknowledgeScriptRun(run.scriptId) // 클릭 = 확인 — 칩만 내리고 결과·로그는 남는다
        state.revealScript(scriptId: run.scriptId) // 종료 로그는 도크에 있다
    }

    // MARK: 문구

    private func runningHelp(_ active: [ScriptRun]) -> String {
        let latest = active[0]
        if active.count > 1 {
            return "스크립트 \(active.count)개 실행 중 (최신: \(latest.name)) — 클릭해 출력 보기"
        }
        return "‘\(latest.name)’ 실행 중 — 클릭해 출력 보기"
    }

    private func lingerHelp(_ run: ScriptRun) -> String {
        "‘\(run.name)’ \(ScriptStatusStyle.label(run.state)) — 클릭해 로그 보기"
    }
}
