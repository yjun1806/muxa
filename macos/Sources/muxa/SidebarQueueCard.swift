import SwiftUI

/// 주의 큐 카드 — 트리 맨 위. **기다리는 세션이 하나도 없으면 아예 렌더하지 않는다**
/// (빈 상태를 위한 빈 카드는 크롬 소음이다).
///
/// 옛 한 줄 헤더("메인 가 입력을 기다립니다")의 두 침묵을 고친다:
/// ① 어느 워크스페이스의 "메인"인지 말하지 않았다 → 행마다 **워크스페이스 › 프로젝트** 경로.
/// ② 여럿이면 "N개 프로젝트"로 뭉갰다 → **개별 행 나열**, 행 클릭 = 그 프로젝트 대기 탭으로 지목 점프
///    (이름을 다 보여주므로 "첫 이름을 말하면 ⌘⇧A와 어긋난다"던 거짓말 문제가 해소된다. ⌘⇧A 순환은 그대로).
///
/// 카드 표현은 **칸 테두리의 대기 어휘를 공유**한다 — bg 면 + 로즈 링 펄스("전체 링 + 펄스", DESIGN §4).
struct SidebarQueueCard: View {
    let state: AppState
    /// 대기 경과("4m") 재수확 트리거 — **카드 로컬 1초 tick**(카드가 안 뜨면 타이머도 없다, ScriptStrip과 같은 규칙).
    @State private var now = Date()

    /// 카드가 트리를 밀어내면 주객전도 — 이 수를 넘으면 "그 외 N곳" 접기 행.
    private static let maxRows = 4

    var body: some View {
        let entries = state.waitingQueue
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if entries.count > 1 { header(entries.count) } // 하나일 땐 행이 곧 머리글 — 개수는 소음
                ForEach(entries.prefix(Self.maxRows)) { entry in
                    row(entry, isFirst: entry.id == entries.first?.id)
                }
                if entries.count > Self.maxRows { overflowRow(entries.count - Self.maxRows) }
            }
            .padding(Space.xs)
            .background(QueuePulseRing()) // bg 카드 + 로즈 링 펄스(칸 테두리 대기 어휘)
            .tick(every: 1, into: $now)   // @State 갱신이 카드만 리렌더 → 경과가 굳지 않는다
        }
    }

    /// 머리글 — "입력 대기 N" + ⌘⇧A. 소섹션 머리글 문법(`muxaLabel`, 한글이라 대문자 규칙만 제외).
    private func header(_ count: Int) -> some View {
        HStack(spacing: Space.xs) {
            Text("입력 대기")
                .font(.muxaLabel)
                .tracking(Tracking.label)
                .foregroundStyle(Color.pWaiting)
            Text("\(count)")
                .font(.muxaMono(.caption, weight: .semibold))
                .foregroundStyle(Color.pWaiting)
            Spacer(minLength: Space.xs)
            Text("⌘⇧A")
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: RowHeight.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("입력 대기 \(count)곳")
    }

    /// 대기 한 행 — ⏸ + 워크스페이스 › **프로젝트** + 경과(모노). 클릭 = 그 프로젝트 대기 탭으로.
    /// **큐의 머리(첫 행 = `nextWaiting`)만 펄스·로즈 경과** — 전부 펄스면 아무것도 강조되지 않는다.
    /// ("다음 ⌘⇧A 목적지"라고는 말하지 않는다 — 순환은 커서 뒤 첫 슬롯이라 첫 행이 아닐 수 있다.)
    private func row(_ entry: AppState.WaitingQueueEntry, isFirst: Bool) -> some View {
        let elapsed = entry.waitingSeconds.map(RelativeTime.compact)
        // 상태 문구는 사이드바 행과 같은 헬퍼(`RelativeTime.waitingLabel`) — 포맷이 갈라지지 않게.
        let desc = "\(entry.ref.workspaceName) \(entry.ref.projectName) — "
            + (entry.waitingSeconds.map { RelativeTime.waitingLabel(seconds: $0) } ?? "입력 대기")
        return Button { state.jumpToWaiting(projectId: entry.ref.projectId) } label: {
            HStack(spacing: Space.sm) {
                glyph(pulsing: isFirst)
                // 워크스페이스는 문맥(무채), 프로젝트가 주어(semibold) — 브레드크럼과 같은 순서.
                Text(entry.ref.workspaceName)
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1).truncationMode(.tail)
                Text("›")
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                Text(entry.ref.projectName)
                    .font(entry.usesMonoName ? .muxaMono(.label, weight: .semibold)
                                             : .muxa(.label, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1) // 좁아지면 문맥(워크스페이스)이 먼저 잘린다 — 주어는 지킨다
                Spacer(minLength: Space.xs)
                if let elapsed {
                    Text(elapsed)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(isFirst ? Color.pWaiting : Color.pMuted)
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: RowHeight.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ListRowFill())
        .clickCursor()
        .help("\(desc). 클릭해 이동")
        .accessibilityLabel("\(desc). 이동")
    }

    /// 접기 행 — "그 외 N곳". 클릭 = ⌘⇧A와 같은 순환 점프(순회 순서가 같아 거짓말이 없다).
    private func overflowRow(_ count: Int) -> some View {
        Button { state.jumpToNextWaiting() } label: {
            HStack(spacing: Space.sm) {
                Color.clear.frame(width: IconSize.statusSlot, height: IconSize.statusSlot) // 글리프 슬롯 정렬
                Text("그 외 \(count)곳")
                    .font(.muxa(.label))
                    .foregroundStyle(Color.pMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: RowHeight.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ListRowFill())
        .clickCursor()
        .help("대기 \(count)곳 더 — 클릭해 다음 대기로 이동")
        .accessibilityLabel("그 외 입력 대기 \(count)곳, 다음 대기로 이동")
    }

    /// ⏸ 글리프 — 사이드바 행과 같은 어휘(`StatusStyle.attention`). 첫 행만 펄스.
    @ViewBuilder
    private func glyph(pulsing: Bool) -> some View {
        let base = Image(systemName: StatusStyle.glyph(.attention))
            .font(.muxa(.caption, weight: .semibold))
            .foregroundStyle(StatusStyle.color(.attention))
            .frame(width: IconSize.statusSlot, height: IconSize.statusSlot)
        if pulsing {
            base.symbolEffect(.pulse, options: .repeating)
        } else {
            base
        }
    }
}

/// 카드의 바탕 — `bg` 면 + **로즈 링 펄스**. 칸 테두리의 대기 표현("전체 링 + 펄스")과 같은 어휘라
/// "저 카드 = 대기 중인 칸들의 요약"으로 읽힌다. reduce-motion이면 정적 링(움직임 없이 의미는 유지).
private struct QueuePulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 링 펄스의 알파 구간·주기 — 값은 여기 한 곳에만.
    private static let baseAlpha = 0.4
    private static let peakAlpha = 1.0
    private static let period = 1.8

    var body: some View {
        if reduceMotion {
            ring(alpha: Self.baseAlpha)
        } else {
            // 30fps 상한 — 1.8s 알파 페이드에 주사율(최대 120fps)은 낭비다.
            // (SpinnerArc는 **회전**이라 무상한이 맞다 — 펄스는 아니다.)
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                // 시간구동 사인 펄스 — `repeatForever`와 달리 뷰 재활용에도 위상이 끊기거나 남지 않는다(SpinnerArc와 동일).
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (sin(t / Self.period * 2 * .pi) + 1) / 2
                ring(alpha: Self.baseAlpha + (Self.peakAlpha - Self.baseAlpha) * phase)
            }
        }
    }

    private func ring(alpha: Double) -> some View {
        RoundedRectangle(cornerRadius: Radius.lg) // 안쪽 행 sm + 인셋 xs = lg — 동심원 규칙
            .fill(Color.pBg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.pWaiting.opacity(alpha), lineWidth: RowHeight.hairline)
            )
    }
}
