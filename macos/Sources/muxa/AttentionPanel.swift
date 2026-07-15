import SwiftUI

/// 상단바 알림 벨 — 안 읽은 이력 수를 배지로 얹고, 누르면 인박스 팝오버를 연다.
/// 배지("지금 상태")와 달리 인박스는 "자리 비웠다 돌아왔을 때의 복구 동선"이라 전역(모든 워크스페이스)이다.
struct AttentionBell: View {
    let state: AppState
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unread > 0 ? "bell.badge" : "bell")
                    .font(.muxa(.body))
                    .foregroundStyle(open || unread > 0 ? Color.pFg : Color.pMuted)
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.muxaMono(.nano, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12)
                        .frame(height: 12)
                        .background(Color(nsColor: Palette.borderActivity), in: Capsule())
                        .offset(x: 7, y: -6)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
        .clickCursor()
        .frame(width: IconSize.control, height: IconSize.control)
        .background(open ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help("알림 인박스")
        // 인박스를 여는 순간 다 봤음 처리(벨 배지 0으로) — 여는 즉시 읽음이 표준 인박스 UX.
        .onChange(of: open) { _, isOpen in if isOpen { state.attention.markAllRead() } }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AttentionInbox(state: state) { open = false }
        }
    }

    // 놓친 알림 + 처리 안 한 워크트리 제안. 인박스를 열면 알림은 읽음 처리되지만 제안은 추가/무시할 때까지
    // 남아 배지를 유지한다 — "아직 결정할 워크트리가 있다"는 지속 넛지(orca 인박스와 같은 취지).
    private var unread: Int { state.attention.unreadCount + offerCount }

    private var offerCount: Int {
        // 공유 repo에서 같은 워크트리가 두 워크스페이스로 나올 수 있으니 경로 유니크로 센다(이중 카운트 방지).
        Set(state.workspaces.flatMap { ws in state.worktreeOffers(for: ws).map(\.path) }).count
    }
}

/// 인박스 팝오버 본문 — 놓친 주의 이력 목록(최신 우선). 항목 클릭 → 그 칸으로 점프.
struct AttentionInbox: View {
    let state: AppState
    /// 항목 클릭 후 팝오버를 닫기 위한 콜백(부모 상태 소유).
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            HDivider()
            if !offers.isEmpty {
                offerSection
                HDivider()
            }
            if entries.isEmpty {
                // offer만 있고 놓친 활동이 없으면 빈 상태 대신 공간을 채운다(offer 섹션은 위에 이미 보인다).
                if offers.isEmpty { emptyState } else { Spacer(minLength: 0) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            Rectangle().fill(Color.pBorder.opacity(0.5)).frame(height: 1)
                        }
                    }
                }
            }
            HDivider()
            hookFooter
        }
        .frame(width: 320, height: 380)
        .background(Color.pPanel)
    }

    /// 훅 상태 푸터 — 알림 품질의 근원을 정직하게 드러낸다.
    ///
    /// 훅이 없으면 muxa는 출력 idle 타이머로 **추정**할 뿐이라 완료·대기 판정이 부정확하다.
    /// "설치됨"과 "동작 중"을 구분해 보여주는 게 핵심 — settings.json에 썼다는 것과 훅이 실제로
    /// 발화한다는 것은 다르다. 신호가 한 번 도착해야 "동작 중"으로 승격된다.
    private var hookFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: hookIcon)
                .font(.muxa(.label))
                .foregroundStyle(Color(nsColor: hookColor))
            Text(state.hookStatus.label)
                .font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(1)
            Spacer(minLength: 4)
            if needsInstall {
                Button { state.installClaudeHooks() } label: {
                    Text("설치").font(.muxa(.caption, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pBrand)
                .help("~/.claude/settings.json에 muxa 훅을 추가한다(기존 훅은 보존, 백업 생성)")
            } else {
                // 제거 경로가 없으면 사용자는 settings.json을 손으로 고쳐야 한다 — 우리가 넣었으면 우리가 뺀다.
                Button { state.uninstallClaudeHooks() } label: {
                    Text("제거").font(.muxa(.caption))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pMuted)
                .help("settings.json에서 muxa 훅만 제거한다(다른 훅은 그대로)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private var needsInstall: Bool {
        switch state.hookStatus {
        case .notInstalled, .failed: return true
        case .installed, .verified: return false
        }
    }

    private var hookIcon: String {
        switch state.hookStatus {
        case .verified: return "bolt.fill"
        case .installed: return "bolt"
        case .notInstalled: return "bolt.slash"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var hookColor: NSColor {
        switch state.hookStatus {
        case .verified: return Palette.gitAdded
        case .installed: return Palette.borderActivity
        case .notInstalled: return Palette.muted
        case .failed: return Palette.gitDeleted
        }
    }

    /// 최신 우선으로 보여준다(로그는 발생 순 보관).
    private var entries: [AttentionEntry] { state.attention.entries.reversed() }

    // MARK: 새 워크트리 "추가?" 제안 (D31) — 감지됨 − (Project ∪ baseline). 인박스는 전역이라 모든 워크스페이스 합산.

    /// 워크스페이스+경로 복합 신원 — 두 워크스페이스가 같은 repo를 공유하면 같은 경로가 둘 나오므로
    /// `wt.path`만으로는 ForEach id가 충돌한다(리뷰). ws.id를 섞어 안정 신원을 만든다.
    private struct OfferItem: Identifiable {
        let ws: Workspace
        let wt: GitWorktree
        var id: String { ws.id + "\u{0}" + wt.path }
    }

    private var offers: [OfferItem] {
        state.workspaces.flatMap { ws in state.worktreeOffers(for: ws).map { OfferItem(ws: ws, wt: $0) } }
    }

    private var offerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.muxa(.label)).foregroundStyle(Color.pBrand)
                Text("새 워크트리 감지").font(.muxa(.caption, weight: .semibold)).foregroundStyle(Color.pMuted)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            // 병렬 워크트리가 많으면 offer도 많다 — 고정 인박스 높이를 넘지 않도록 스크롤로 가둔다(리뷰).
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(offers) { item in offerRow(ws: item.ws, wt: item.wt) }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    /// 한 줄 — [브랜치/워크스페이스][추가][무시]. 추가=승격, 무시=baseline. 어느 쪽이든 목록에서 사라진다(반응).
    private func offerRow(ws: Workspace, wt: GitWorktree) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(wt.displayName).font(.muxa(.body)).foregroundStyle(Color.pFg).lineLimit(1)
                Text(ws.name).font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { state.importWorktree(wt, in: ws.id) } label: {
                Text("추가").font(.muxa(.caption, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Color.pBrand).clickCursor()
            .help("이 워크트리를 사이드바에 프로젝트로 추가한다")
            Button { state.dismissWorktree(wt, in: ws.id) } label: {
                Text("무시").font(.muxa(.caption))
            }
            .buttonStyle(.plain).foregroundStyle(Color.pMuted).clickCursor()
            .help("이 워크트리를 다시 제안하지 않는다")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell").font(.muxa(.label)).foregroundStyle(Color.pMuted)
            Text("알림 인박스").font(.muxa(.body, weight: .semibold)).foregroundStyle(Color.pFg)
            Text("\(state.attention.entries.count)")
                .font(.muxaMono(.caption)).foregroundStyle(Color.pMuted.opacity(0.7))
            Spacer(minLength: 0)
            if !entries.isEmpty {
                Button { state.attention.clear() } label: {
                    Text("모두 지우기").font(.muxa(.caption))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pMuted)
                .help("이력 비우기")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var emptyState: some View {
        EmptyState(icon: "bell.slash", title: "놓친 알림 없음", compact: true)
    }

    /// 이력 한 줄 — [종류 아이콘][제목 / 위치][상대 시각]. 클릭하면 그 칸으로 점프하고 팝오버를 닫는다.
    private func row(_ entry: AttentionEntry) -> some View {
        Button {
            state.revealAttention(entry)
            onClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.kind.icon)
                    .font(.muxa(.body))
                    .foregroundStyle(Color(nsColor: entry.kind.color))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? entry.kind.label : entry.title)
                        .font(.muxa(.body)).foregroundStyle(Color.pFg).lineLimit(1)
                    let location = state.attentionLocationLabel(projectId: entry.projectId)
                    if !location.isEmpty {
                        Text(location)
                            .font(.muxa(.caption)).foregroundStyle(Color.pMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(Self.relativeTime(entry.date))
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    /// 상대 시각 — 방금 / N분 / N시간 / N일. 표시 전용(정렬은 seq).
    static func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "방금" }
        if secs < 3600 { return "\(secs / 60)분" }
        if secs < 86400 { return "\(secs / 3600)시간" }
        return "\(secs / 86400)일"
    }
}
