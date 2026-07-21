import SwiftUI

/// 명령 탭 v2의 행들 — 즐겨찾기 · 히스토리(펼침) · 실행 내역. 상태 글리프·색은 `ScriptStatusStyle` 공유.

/// lastRun 상대시각 — "2분 전"(사용자 로케일). now 주입으로 tick마다 갱신.
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
    /// 소요시간 "2.1s" · "1m 30s".
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }
}

/// 즐겨찾기 행 — 이름(친근) 또는 명령, 즉시 실행(▶ 상시), ★로 해제. 클릭=상세.
struct CommandFavoriteRow: View {
    let entry: CommandEntry
    let now: Date
    let run: ScriptRun?
    let selected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onUnfavorite: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Space.sm) {
                Image(systemName: ScriptStatusStyle.glyph(run?.state)).font(.muxa(.label))
                    .foregroundStyle(ScriptStatusStyle.color(run?.state)).frame(width: IconSize.statusSlot)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.name ?? entry.command).font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1)
                    Text(subtitle).font(.muxa(.micro)).foregroundStyle(Color.pMuted).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                if hovered { RowIconButton(icon: "star.fill", help: "즐겨찾기 해제", action: onUnfavorite) }
                if run?.isRunning != true { RowIconButton(icon: "play.fill", help: "실행", action: onRun) }
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
        if entry.name != nil { return entry.command }        // 이름 있으면 명령을 부제로
        if let last = entry.lastRunAt { return CommandRelativeTime.string(last, now: now) }
        return entry.command
    }
}

/// 히스토리 행 — 명령(모노) + lastRun·횟수. 클릭하면 실행 내역이 펼쳐진다. hover ☆즐겨찾기 ▶재실행 🗑삭제.
struct CommandHistoryRowV2: View {
    let entry: CommandEntry
    let now: Date
    let run: ScriptRun?
    let expanded: Bool
    let selectedExec: String?
    let onToggle: () -> Void
    let onRun: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onSelectExec: (String) -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Space.sm) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.muxa(.micro)).foregroundStyle(Color.pMuted).frame(width: IconSize.statusSlot)
                    Image(systemName: ScriptStatusStyle.glyph(run?.state)).font(.muxa(.label))
                        .foregroundStyle(ScriptStatusStyle.color(run?.state))
                    Text(entry.command).font(.muxaMono(.label)).foregroundStyle(Color.pFg).lineLimit(1)
                    Spacer(minLength: Space.xs)
                    if hovered {
                        RowIconButton(icon: "star", help: "즐겨찾기 추가", action: onFavorite)
                        RowIconButton(icon: "play.fill", help: "재실행", action: onRun)
                        if run?.isRunning != true { RowIconButton(icon: "trash", help: "삭제", action: onDelete) }
                    } else {
                        Text(subtitle).font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                    }
                }
                .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
                .background(hovered ? Color.pBtnHover : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).clickCursor().onHover { hovered = $0 }

            if expanded {
                ForEach(entry.executions) { exec in
                    ExecMetaRow(exec: exec, now: now, selected: selectedExec == exec.id,
                                onTap: { onSelectExec(exec.id) })
                }
                .padding(.leading, Space.md)
            }
        }
    }

    private var subtitle: String {
        if run?.isRunning == true { return "실행 중" }
        let rel = entry.lastRunAt.map { CommandRelativeTime.string($0, now: now) } ?? ""
        return entry.runCount > 1 ? "\(rel) · \(entry.runCount)회" : rel
    }
}

/// 실행 내역 한 줄 — 결과(✓/✗/⟳)·시각·소요·exit code. 클릭하면 그 실행의 저장 로그를 상세로 연다.
struct ExecMetaRow: View {
    let exec: CommandExecution
    let now: Date
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Space.sm) {
                Image(systemName: glyph).font(.muxa(.micro)).foregroundStyle(tint).frame(width: IconSize.statusSlot)
                Text(CommandRelativeTime.string(exec.startedAt, now: now))
                    .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.xs)
                Text(detail).font(.muxaMono(.caption)).foregroundStyle(tint)
            }
            .padding(.horizontal, Space.sm).frame(height: RowHeight.tight)
            .background(rowBackground(selected: selected, hovered: hovered),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).clickCursor().onHover { hovered = $0 }
    }

    private var glyph: String {
        guard let code = exec.exitCode else { return "circle.dotted" } // 실행 중/미상
        return code == 0 ? "checkmark" : "xmark"
    }
    private var tint: Color {
        guard let code = exec.exitCode else { return Color.pMuted }
        return code == 0 ? Color(nsColor: Palette.gitAdded) : Color(nsColor: Palette.gitDeleted)
    }
    private var detail: String {
        var parts: [String] = []
        if let d = exec.duration { parts.append(CommandRelativeTime.duration(d)) }
        if let c = exec.exitCode, c != 0 { parts.append("exit \(c)") }
        return parts.joined(separator: " · ")
    }
}

/// 행 hover 배경 — 선택(눌린 유지) → hover → 평시.
private func rowBackground(selected: Bool, hovered: Bool) -> Color {
    if selected { return .pBtnActive }
    return hovered ? .pBtnHover : .clear
}

/// 행 오른쪽의 작은 아이콘 버튼(실행·즐겨찾기·삭제).
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
