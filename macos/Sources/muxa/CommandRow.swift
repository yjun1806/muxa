import SwiftUI

/// 명령 탭의 행 두 종 — 등록 명령(꺼냄)과 히스토리(최근 실행). 스크립트+일회용 통합의 표면.
/// 상태 글리프·색은 서비스/스크립트와 같은 `ScriptStatusStyle`을 공유한다(사각형 축).

/// lastRun 상대시각 — "2분 전"(사용자 로케일). now 주입으로 tick마다 갱신된다.
enum CommandRelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = .autoupdatingCurrent
        f.unitsStyle = .abbreviated
        return f
    }()
    static func string(_ date: Date, now: Date) -> String {
        formatter.localizedString(for: date, relativeTo: now)
    }
}

/// 등록된 명령 행 — 이름(친근한 라벨) + 상태/실행시각, hover ▶=실행.
struct CommandRegisteredRow: View {
    let script: Script
    let lastRunAt: Date?
    let now: Date
    let run: ScriptRun?
    let selected: Bool
    let action: () -> Void
    let onRun: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: ScriptStatusStyle.glyph(run?.state))
                    .font(.muxa(.label)).foregroundStyle(ScriptStatusStyle.color(run?.state))
                    .frame(width: IconSize.statusSlot)
                VStack(alignment: .leading, spacing: 0) {
                    Text(script.name).font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1)
                    Text(subtitle).font(.muxa(.micro)).foregroundStyle(Color.pMuted).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                if hovered && run?.isRunning != true {
                    RowIconButton(icon: "play.fill", help: "실행", action: onRun)
                }
            }
            .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
            .background(rowBackground(selected: selected, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).clickCursor().onHover { hovered = $0 }
    }

    private var subtitle: String {
        if run?.isRunning == true { return "실행 중" }
        if let lastRunAt { return CommandRelativeTime.string(lastRunAt, now: now) }
        return script.command // 한 번도 안 돌린 등록 명령 — 명령 자체를 보인다
    }
}

/// 히스토리 행 — 명령(모노) + lastRun·횟수, hover ▶재실행 ⊞등록 🗑삭제.
struct CommandHistoryRow: View {
    let entry: CommandHistoryEntry
    let now: Date
    let run: ScriptRun?
    let selected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onRegister: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Space.sm) {
                Image(systemName: ScriptStatusStyle.glyph(run?.state))
                    .font(.muxa(.label)).foregroundStyle(ScriptStatusStyle.color(run?.state))
                    .frame(width: IconSize.statusSlot)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.command).font(.muxaMono(.label)).foregroundStyle(Color.pFg).lineLimit(1)
                    Text(subtitle).font(.muxa(.micro)).foregroundStyle(Color.pMuted).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                if hovered {
                    RowIconButton(icon: "play.fill", help: "재실행", action: onRun)
                    RowIconButton(icon: "plus.square", help: "스크립트로 등록", action: onRegister)
                    if run?.isRunning != true {
                        RowIconButton(icon: "trash", help: "기록 삭제", action: onDelete)
                    }
                }
            }
            .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
            .background(rowBackground(selected: selected, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).clickCursor().onHover { hovered = $0 }
    }

    private var subtitle: String {
        if run?.isRunning == true { return "실행 중" }
        let rel = CommandRelativeTime.string(entry.lastRunAt, now: now)
        return entry.runCount > 1 ? "\(rel) · \(entry.runCount)회" : rel
    }
}

/// 행 hover 배경 — 선택(눌린 유지) → hover → 평시. FooterChip 색규칙과 같은 어휘.
private func rowBackground(selected: Bool, hovered: Bool) -> Color {
    if selected { return .pBtnActive }
    return hovered ? .pBtnHover : .clear
}

/// 행 오른쪽의 작은 아이콘 버튼(실행·등록·삭제) — 부모 행 버튼 위에 겹쳐도 제 클릭을 먹는다.
struct RowIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                .frame(width: IconSize.statusSlot, height: RowHeight.tight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).clickCursor().help(help)
    }
}
