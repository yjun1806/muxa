import SwiftUI

/// Claude 사용량 칩 — [✳ | 5h ▬ 9% | wk ▬ 54% | fable ▬ 12%]. 클릭하면 상세/설정 팝오버가 열린다.
///
/// 푸터·헤더 어디에 놓여도 같은 칩이다(`StatusBarSettings.position`이 자리를 정한다) — 그래서
/// StatusBar의 인라인 뷰가 아니라 독립 컴포넌트로 뽑았다. 무엇을 보일지(리셋 시각·fable)는
/// **전부 설정에서** 온다. 상태(조회·실패·값)는 `ClaudeUsageService` 싱글턴이 관측된다.
struct UsageChip: View {
    let state: AppState

    private let usage = ClaudeUsageService.shared
    private let settings = StatusBarSettings.shared

    @State private var showUsage = false
    /// 리셋 카운트다운("3h 38m")이 굳지 않도록 갱신 주기마다 흐르는 현재 시각.
    @State private var now = Date()

    /// 활성 프로젝트의 실효 경로 — 프로젝트를 바꾸면 사용량을 다시 조회하는 `.task`의 트리거.
    private var projectDir: String? {
        guard let ws = state.activeWorkspace else { return nil }
        return ws.activeProject?.path ?? ws.path
    }

    var body: some View {
        FooterChip(isOpen: $showUsage,
                   help: "claude 사용량 — 클릭해 상세 보기·설정") {
            HStack(alignment: .center, spacing: Space.sm) {
                ClaudeMark(size: IconSize.inlineMark)
                if shown.isEmpty {
                    Text(placeholder)
                        .font(.muxa(.label))
                        .foregroundStyle(Color.pMuted.opacity(0.7))
                } else {
                    ForEach(shown) { limit in
                        VDivider(height: 12)
                        limitView(limit)
                    }
                    if usage.failed {
                        // 값은 있지만 마지막 갱신이 실패 — 지금 보이는 건 이전 조회 결과다.
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.muxa(.micro))
                            .foregroundStyle(UsageColor.stale)
                            .help("갱신 실패 — 이전 값입니다")
                    }
                }
                if usage.loading {
                    ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 12, height: 12)
                }
            }
        }
        .muxaPopover(isPresented: $showUsage) {
            UsagePopover()
        }
        .task(id: projectDir) {
            await usage.refreshIfStale() // 프로젝트를 바꾸면 캐시가 만료됐는지 다시 본다
        }
        .tick(every: settings.refreshIntervalSec, into: $now) // 리셋 카운트다운·갱신 주기
        .onChange(of: now) { _, _ in
            Task { await usage.refreshIfStale() } // 만료됐으면 조용히 재조회
        }
    }

    /// 상태바에 띄울 한도 — 세션·주간은 항상, fable은 설정 시. 순서는 세션 → 주간 → fable.
    private var shown: [UsageLimit] {
        let all = usage.limits
        let session = all.first(where: \.isSession)
        let weekly = all.first { !$0.isSession && !$0.isModelScoped }
        let fable = settings.showFable ? all.first(where: \.isModelScoped) : nil
        return [session, weekly, fable].compactMap { $0 }
    }

    /// 이 한도 옆에 리셋 시각을 붙일지 — 세션·주간은 각자 토글, fable은 시간 표시 안 함.
    private func showsReset(_ limit: UsageLimit) -> Bool {
        if limit.isSession { return settings.showSessionReset }
        if limit.isModelScoped { return false }
        return settings.showWeeklyReset
    }

    /// 보여줄 한도가 없을 때의 문구 — 조회 전·실패·빈 응답을 구분한다.
    private var placeholder: String {
        switch usage.state {
        case .idle: return "사용량 …"
        case .failed: return "사용량 —"
        case .empty, .ok: return "사용량 없음"
        }
    }

    /// 한도 하나 — [라벨][막대][%] + (설정 시)[⏲ 남은 시간]. 숫자가 주인공, 라벨은 보조.
    private func limitView(_ limit: UsageLimit) -> some View {
        HStack(alignment: .center, spacing: Space.xs) {
            Text(limit.label)
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted)
            Meter(value: Double(limit.percent) / 100, color: UsageColor.meter(limit), width: 28, height: 4)
            Text("\(limit.percent)%")
                .font(.muxaMono(.label, weight: .semibold))
                .foregroundStyle(UsageColor.text(limit))
            if showsReset(limit), let reset = ClaudeUsage.resetShort(limit.resetsAt, now: now) {
                // 시계 아이콘이 없으면 "3h 38m"이 또 하나의 사용량 수치처럼 읽힌다 — 남은 시간임을 표시.
                Image(systemName: "clock").font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                Text(reset).font(.muxaMono(.caption)).foregroundStyle(Color.pMuted)
            }
        }
        .help(detail(limit))
    }

    /// 항목 툴팁 — 리셋 시각을 hover로 되돌려준다.
    private func detail(_ limit: UsageLimit) -> String {
        let base = "\(limit.label) 한도 \(limit.percent)% 사용"
        guard let reset = ClaudeUsage.resetText(limit.resetsAt, now: now) else { return base }
        return "\(base) · \(reset) 리셋"
    }
}
