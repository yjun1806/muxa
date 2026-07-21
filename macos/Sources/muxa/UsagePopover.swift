import SwiftUI

/// claude 사용량 상세 팝오버 — 상태바의 사용량 칩을 클릭하면 열린다.
/// 한도별로 [이름 / 넓은 막대 / N% 사용 · 언제 리셋]을 보여준다(상태바는 좁아서 축약형만 보인다).
///
/// 셸(헤더·구분선·폭)은 `FooterPopover`가 맡는다 — 서비스·백그라운드 팝오버와 같은 틀.
struct UsagePopover: View {
    /// 톱니 클릭 — 팝오버를 닫고 설정 사이드 패널의 "사용량 표시" 섹션을 연다(호출자가 배선).
    let onOpenSettings: () -> Void

    private let usage = ClaudeUsageService.shared

    /// 팝오버가 떠 있는 동안 "N분 전 갱신"이 굳지 않도록 1분마다 흐르는 현재 시각.
    @State private var now = Date()

    /// 막대 폭 = 팝오버 폭 − 좌우 인셋. 헤더·행과 같은 선에서 시작하고 끝난다.
    private var barWidth: CGFloat { PopoverWidth.footer - Space.panelInset * 2 }

    var body: some View {
        // 표시 설정(무엇을 보일지·위치·갱신)은 이제 **설정 사이드 패널**이 맡는다 — 이 팝오버는 상세만.
        // (설정을 여기 넣었더니 높이가 바뀌며 위치가 튀고 뷰어가 깜빡였다 — 팝오버는 크기가 안정적이어야 한다.)
        FooterPopover(title: "Claude", subtitle: updatedText) {
            ClaudeMark(size: IconSize.mark)
        } accessory: {
            // 수동 갱신 — **캐시 TTL만** 우회한다. 429/실패 백오프 창은 안 뚫고(그러면 리밋이 연장된다),
            // 마지막 성공이 30초 안이면 무시한다(연타 방지). 그래서 사람이 눌러도 예산을 안 갉는다.
            HStack(spacing: Space.xs) {
                FooterAction(icon: "arrow.clockwise", help: refreshHelp, disabled: refreshBlocked) {
                    Task { await usage.manualRefresh() }
                }
                FooterAction(icon: "gearshape", help: "사용량 표시 설정") { onOpenSettings() }
            }
        } content: {
            if usage.limits.isEmpty {
                FooterHint(title: emptyTitle, detail: emptyDetail)
            } else {
                // 한도 하나가 세 줄짜리 덩어리라, 덩어리 사이(md)를 줄 사이(xs)보다 확실히 벌려야 묶음이 읽힌다.
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(usage.limits) { limit in
                        row(limit)
                    }
                }
                .footerBlock()
            }
        }
        .tick(every: 60, into: $now) // "3분 전 갱신"이 굳지 않게(팝오버가 열려 있는 동안만)
    }

    /// 수동 갱신을 지금 누를 수 없나 — 조회 중이거나 429/실패 백오프 창 안(그땐 회색으로 둔다).
    private var refreshBlocked: Bool { usage.loading || usage.manualBlockedUntil != nil }

    /// 새로고침 버튼 툴팁 — 왜 못 누르는지(제한 중 N분 후)까지 알린다.
    private var refreshHelp: String {
        if usage.loading { return "갱신 중…" }
        if let until = usage.manualBlockedUntil {
            let minutes = max(1, Int(until.timeIntervalSince(now)) / 60)
            return "요청 제한 중 · 약 \(minutes)분 후"
        }
        return "지금 갱신"
    }

    /// 보여줄 한도가 없을 때 — 조회 전·실패·레이트리밋·빈 응답을 구분해 원인을 짐작할 수 있게 한다.
    private var emptyTitle: String {
        switch usage.state {
        case .idle: return "불러오는 중…"
        case .failed: return "사용량을 가져오지 못했습니다"
        case .rateLimited: return "요청이 잠시 제한되고 있습니다"
        case .empty, .ok: return "표시할 한도가 없습니다"
        }
    }

    private var emptyDetail: String {
        switch usage.state {
        case .idle: return "claude CLI에 한도를 물어보는 중입니다."
        case .failed: return "로그인이 필요하거나 일시적인 오류입니다.\n새로고침으로 다시 시도해 보세요."
        case .rateLimited:
            // 로그인 문제가 아니다 — 그렇게 안내하면 사용자가 멀쩡한 로그인을 갈아엎는다(실측 오진).
            if let until = usage.rateLimitedUntil, until > now {
                let minutes = max(1, Int(until.timeIntervalSince(now)) / 60)
                return "서버가 사용량 조회를 제한 중입니다(로그인 문제 아님).\n약 \(minutes)분 후 자동으로 다시 시도합니다."
            }
            return "서버가 사용량 조회를 제한 중입니다(로그인 문제 아님).\n잠시 후 자동으로 다시 시도합니다."
        case .empty, .ok: return "이 계정에 적용된 사용 한도가 없습니다."
        }
    }

    /// 한도 한 덩이 — 세 줄로 짝을 맞춘다. 한 줄에 다 넣으면 긴 리셋 문구가 어중간하게 접힌다.
    ///
    ///   세션                     3시간 38분 후   ← 이름 / 남은 시간
    ///   ▬▬▬░░░░░░░░░░░░░░░
    ///   9% 사용                     오후 3:39   ← 소진율 / 리셋 시각
    ///
    /// 왼쪽은 "지금 얼마나 썼나", 오른쪽은 "언제 풀리나" — 열이 의미로 나뉜다.
    private func row(_ limit: UsageLimit) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(name(limit))
                    .font(.muxa(.body, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                Spacer(minLength: Space.md)
                if let remaining = ClaudeUsage.resetText(limit.resetsAt, now: now) {
                    Text(remaining)
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                }
            }
            Meter(value: Double(limit.percent) / 100,
                  color: UsageColor.meter(limit, mode: StatusBarSettings.shared.meterColorMode),
                  width: barWidth, height: 6)
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("\(limit.percent)% 사용")
                    .font(.muxa(.label))
                    .foregroundStyle(UsageColor.text(limit))
                Spacer(minLength: Space.md)
                if let clock = ClaudeUsage.resetClock(limit.resetsAt, now: now) {
                    Text(clock)
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted.opacity(0.7))
                }
            }
        }
        .lineLimit(1) // 어떤 문구가 길어져도 접히지 않고 잘린다(레이아웃이 흔들리지 않게)
        .frame(width: barWidth)
    }

    /// 상태바의 축약 라벨(5h·wk)을 팝오버에선 풀어 쓴다. 모델 스코프(Fable)는 그대로.
    private func name(_ limit: UsageLimit) -> String {
        switch limit.label {
        case "5h": return "세션"
        case "wk": return "주간"
        default: return limit.label
        }
    }

    /// "3분 전 갱신" — 마지막 **성공** 기준. 그 뒤 실패/제한됐으면 그 사실을 덧붙인다.
    private var updatedText: String {
        guard let last = usage.lastSuccess else {
            switch usage.state {
            case .rateLimited: return "요청 제한됨"
            case .failed: return "갱신 실패"
            default: return "불러오는 중…"
            }
        }
        let minutes = Int(now.timeIntervalSince(last)) / 60
        let base = minutes < 1 ? "방금 갱신" : "\(minutes)분 전 갱신"
        switch usage.state {
        case .rateLimited: return "\(base) · 요청 제한됨"
        case .failed: return "\(base) · 마지막 갱신 실패"
        default: return base
        }
    }
}
