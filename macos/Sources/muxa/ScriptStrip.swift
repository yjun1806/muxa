import SwiftUI

/// 푸터의 명령 칩 — 등록된 명령(끝이 있는 명령)의 실행 상태 요약 + 도크 진입점.
///
/// **서비스 칩과 대칭**이 됐다: 클릭하면 팝오버가 아니라 **서비스 도크의 명령 탭**이 열린다
/// (목록·실행·추가·삭제가 전부 도크에 있어 중간 팝오버가 필요 없다 — `ServiceStrip.toggleDock`과 같은 계약).
/// 등록 0개여도 상시로 그려 첫 등록의 발견 지점이 된다(서비스 칩과 같은 철학).
///
/// 네 모드(`ScriptChipMode` 순수 판정): **빈 칩**=플레이스홀더(클릭=도크 명령 탭) /
/// **평시**=개수 칩(클릭=도크) / **실행 중**=[⟳ 이름·경과](클릭=도크 라이브 출력) /
/// **완료 잔류**=✓ 무채·✗ 빨강(클릭=확인 + 도크 종료 로그). 잔류는 클릭·새 실행 시 내려간다(acknowledge).
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

    var body: some View {
        chip
            .frame(height: RowHeight.tight)
            .background(Color.footerChip(isOpen: isOpen, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .onHover { hovered = $0 }
            .animation(Motion.fast, value: hovered)
            .tick(every: 1, into: $now)
    }

    /// 칩 클릭 = 도크 명령 탭 토글(⌘J와 같은 여닫이 — 다시 누르면 닫힌다).
    private func toggleDock() {
        if isOpen { state.closeServiceDock() }
        else { state.openServiceDock(serviceId: nil, tab: .commands) }
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

    /// 등록 0개 — 이름만 말하는 플레이스홀더(ServiceStrip.placeholder와 같은 문법). 클릭 = 도크 명령 탭.
    private var placeholder: some View {
        Button(action: toggleDock) {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.icon).font(.muxa(.micro))
                Text("명령").font(.muxa(.label))
            }
            .foregroundStyle(Color.pMuted)
            .padding(.horizontal, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("명령 — 빌드·테스트처럼 끝이 있는 명령. 클릭해 추가·실행")
        .accessibilityLabel("명령")
    }

    /// 평시 — 개수만 말하는 조용한 칩. 클릭 = 도크 명령 탭.
    private func idleChip(count: Int) -> some View {
        Button(action: toggleDock) {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: ScriptStatusStyle.icon)
                    .font(.muxa(.micro))
                    .foregroundStyle(Color.pMuted)
                Text("\(count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help("명령 \(count)개 — 클릭해 목록·실행 (도크)")
        .accessibilityLabel("명령 \(count)개")
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
