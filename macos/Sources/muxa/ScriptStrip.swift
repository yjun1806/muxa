import SwiftUI

/// 푸터의 명령 칩 — 등록된 명령(끝이 있는 명령)의 **실행 상태**. 클릭하면 서비스 도크의 명령 탭이
/// 열린다(`ServiceStrip`과 같은 계약).
///
/// **평시엔 아예 그리지 않는다**(YJ-8) — 상시 진입점은 액티비티 레일이 맡고, 푸터는 **지금 벌어지는
/// 일**만 말한다(백그라운드 칩의 "0개면 숨김"과 같은 문법). 그래서 푸터에 뭔가 보이면 곧 볼 일이 있다는 뜻이다.
///
/// 네 모드(`ScriptChipMode` 순수 판정) 중 뒤 둘만 그린다: ~~빈 칩~~ / ~~평시 개수~~ /
/// **실행 중**=[⟳ 이름·경과](클릭=도크 라이브 출력) / **완료 잔류**=✓ 무채·✗ 빨강(클릭=확인 + 도크
/// 종료 로그). 잔류는 클릭·새 실행 시 내려간다(acknowledge) — 34pt 레일엔 exit code를 적을 자리가
/// 없어 이 상태는 계속 푸터가 맡는다.
struct ScriptStrip: View {
    let state: AppState
    let project: Project

    @State private var hovered = false
    /// 실행 중/잔류 경과("12s") 갱신용 — **칩 로컬 @State**다. 업데이트는 이 칩만 리렌더한다(footer 전체 아님).
    @State private var now = Date()

    /// 이름 폭 상한 — 긴 명령 이름이 칩 폭을 출렁여 옆 칩(서비스)을 밀지 않게.
    private static let nameMaxWidth: CGFloat = 120

    private var scripts: [Script] { state.scripts(of: project.id) }

    private var mode: ScriptChipMode {
        // 등록 개수(카탈로그) + **모든 명령 실행**(등록·즉석) — 통합 명령 칩이라 즉석 실행도 요약한다.
        ScriptChipMode.judge(scriptCount: scripts.count, runs: state.commandRuns(of: project.id))
    }

    /// 이 칩이 연 도크가 지금 떠 있나 — 배경(눌린 상태 유지)을 서비스 칩과 같은 규칙으로 말한다.
    private var isOpen: Bool { state.showServiceDock && state.dockTab == .commands }

    /// 푸터에 나타나야 하나 — 실행 중이거나 방금 끝난 것이 있을 때만. 평시·빈 상태의 진입점은 레일이 맡는다.
    private var visible: Bool {
        switch mode {
        case .empty, .idle: return false
        case .running, .lingering: return true
        }
    }

    @ViewBuilder var body: some View {
        if visible {
            chip
                .frame(height: RowHeight.tight)
                .background(Color.footerChip(isOpen: isOpen, hovered: hovered),
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .onHover { hovered = $0 }
                .animation(Motion.fast, value: hovered)
                // 경과 갱신 타이머는 **보일 때만** 돈다 — 안 보이면 이 뷰가 아예 없어 tick도 없다.
                .tick(every: 1, into: $now)
        }
    }

    // MARK: 모드별 칩

    @ViewBuilder private var chip: some View {
        switch mode {
        case .running(let active):
            runningChip(active)
        case .lingering(let run):
            lingerChip(run)
        case .empty, .idle:
            EmptyView() // `visible`이 이미 걸렀다 — 여기 오지 않는다.
        }
    }

    /// 실행 중 — [⟳ (N ·) 최신이름 · 12s]. 클릭 = 도크 라이브 출력(revealScript). 팝오버 세그먼트는 없앴다:
    /// 목록·상세가 도크 명령 탭에 다 있어 나눌 이유가 사라졌다(단일 클릭 유닛).
    private func runningChip(_ active: [ScriptRun]) -> some View {
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
            .padding(.horizontal, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(runningHelp(active))
        .accessibilityLabel("명령 \(latest.name) \(ScriptStatusStyle.label(latest.state)) — 클릭해 출력 보기")
    }

    /// 완료 잔류 — [✓ 이름 8s](무채) / [✗ 이름 exit 2](빨강). 색+글리프 이중 신호(DESIGN §2).
    /// 클릭 = 확인(acknowledge — 칩만 내려간다) + 도크 종료 로그 열기(성공·실패 모두 로그가 pane에 보존됨).
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
                    .fixedSize(horizontal: true, vertical: false)
                if let tail = ScriptStatusStyle.tail(run, now: now) {
                    Text(tail)
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(ScriptStatusStyle.color(run.state))
                }
            }
            .padding(.horizontal, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(lingerHelp(run))
        // 색·글리프는 스크린리더에 없다 — exit code까지 말로 한 번 더(DESIGN §2 규칙).
        .accessibilityLabel("명령 \(run.name) \(ScriptStatusStyle.label(run.state))")
    }

    private func lingerClicked(_ run: ScriptRun) {
        state.acknowledgeScriptRun(run.scriptId) // 클릭 = 확인 — 칩만 내리고 결과·로그는 남는다
        state.revealScript(scriptId: run.scriptId) // 종료 로그는 도크에 있다
    }

    // MARK: 문구

    private func runningHelp(_ active: [ScriptRun]) -> String {
        let latest = active[0]
        if active.count > 1 {
            return "명령 \(active.count)개 실행 중 (최신: \(latest.name)) — 클릭해 출력 보기"
        }
        return "‘\(latest.name)’ 실행 중 — 클릭해 출력 보기"
    }

    private func lingerHelp(_ run: ScriptRun) -> String {
        "‘\(run.name)’ \(ScriptStatusStyle.label(run.state)) — 클릭해 로그 보기"
    }
}
