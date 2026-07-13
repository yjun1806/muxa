import SwiftUI

/// claude 사용량 상세 팝오버 — 상태바의 사용량을 클릭하면 열린다.
/// 한도별로 [이름 / 넓은 막대 / N% 사용 · 언제 리셋]을 보여준다(상태바는 좁아서 축약형만 보인다).
struct UsagePopover: View {
    private let usage = ClaudeUsageService.shared

    /// 팝오버가 떠 있는 동안 "N분 전 갱신"이 굳지 않도록 1분마다 흐르는 현재 시각.
    @State private var now = Date()

    private let barWidth: CGFloat = 240

    var body: some View {
        // 한도 하나가 두 줄짜리 덩어리라, 덩어리 사이(lg)를 줄 사이(xs)보다 확실히 벌려야 묶음이 읽힌다.
        VStack(alignment: .leading, spacing: Space.lg) {
            header
            HDivider()
            if usage.limits.isEmpty {
                Text(emptyText)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: barWidth, alignment: .leading)
            } else {
                ForEach(usage.limits) { limit in
                    row(limit)
                }
            }
        }
        .padding(Space.xl)
        .background(Color.pPanel)
        .tick(every: 60, into: $now) // "3분 전 갱신"이 굳지 않게(팝오버가 열려 있는 동안만)
    }

    /// 보여줄 한도가 없을 때 — 조회 전·실패·빈 응답을 구분해 원인을 짐작할 수 있게 한다.
    private var emptyText: String {
        switch usage.state {
        case .idle: return "불러오는 중…"
        case .failed: return "사용량을 가져오지 못했습니다 (로그인 필요 또는 일시적 오류)"
        case .empty, .ok: return "표시할 한도가 없습니다"
        }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            ClaudeMark(size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude").font(.muxa(.title, weight: .semibold)).foregroundStyle(Color.pFg)
                Text(updatedText).font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            .lineLimit(1)
            Spacer(minLength: Space.md)
            if usage.loading {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
            } else {
                IconButton(icon: "arrow.clockwise", help: "새로고침") {
                    Task { await usage.refresh(); now = Date() }
                }
            }
        }
        .frame(width: barWidth) // 아래 한도 행들과 같은 폭 — 새로고침 버튼이 오른쪽 끝에 정렬된다
    }

    /// 한도 한 덩이 — 두 줄로 짝을 맞춘다. 한 줄에 다 넣으면 긴 리셋 문구가 어중간하게 접힌다.
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
            Meter(value: Double(limit.percent) / 100, color: meterColor(limit), width: barWidth, height: 6)
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("\(limit.percent)% 사용")
                    .font(.muxa(.label))
                    .foregroundStyle(textColor(limit))
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

    /// "3분 전 갱신" — 마지막 **성공** 기준. 그 뒤 실패했으면 그 사실을 덧붙인다.
    private var updatedText: String {
        guard let last = usage.lastSuccess else {
            return usage.failed ? "갱신 실패" : "불러오는 중…"
        }
        let minutes = Int(now.timeIntervalSince(last)) / 60
        let base = minutes < 1 ? "방금 갱신" : "\(minutes)분 전 갱신"
        return usage.failed ? "\(base) · 마지막 갱신 실패" : base
    }

    // 색 규칙은 상태바와 같다(UsageColor — 평시 브랜드, 70%↑ 노랑, 90%↑·서버 경고 빨강).
    private func meterColor(_ limit: UsageLimit) -> Color { UsageColor.meter(limit) }
    private func textColor(_ limit: UsageLimit) -> Color { UsageColor.text(limit) }
}
