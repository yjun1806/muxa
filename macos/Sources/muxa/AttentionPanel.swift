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
        .frame(width: 24, height: 24)
        .background(open ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help("알림 인박스")
        // 인박스를 여는 순간 다 봤음 처리(벨 배지 0으로) — 여는 즉시 읽음이 표준 인박스 UX.
        .onChange(of: open) { _, isOpen in if isOpen { state.attention.markAllRead() } }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AttentionInbox(state: state) { open = false }
        }
    }

    private var unread: Int { state.attention.unreadCount }
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
            if entries.isEmpty {
                emptyState
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
        }
        .frame(width: 320, height: 380)
        .background(Color.pPanel)
    }

    /// 최신 우선으로 보여준다(로그는 발생 순 보관).
    private var entries: [AttentionEntry] { state.attention.entries.reversed() }

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
