import SwiftUI

// 알림 진입점(벨)은 우측 **액티비티 레일**의 알림 항목으로 옮겼다(`ActivityRail`) — 배지·읽음 처리
// 동선은 그대로다(`attentionBadgeCount`·`markAllRead`). 인박스 본문(`AttentionInbox`)은 그대로 쓴다.

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
                        // 구분선은 **행 사이에만** — 마지막 행 뒤에 그리면 곧이어 오는 푸터 HDivider와 겹쳐 두 줄이 된다.
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Rectangle().fill(Color.pBorder.opacity(0.5)).frame(height: 1)
                            }
                            row(entry)
                        }
                    }
                }
            }
        }
        // 인스펙터 슬롯을 채운다(폭·높이 유연) — 예전 팝오버의 고정 크기가 아니다.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                MuxaIcon(name: MuxaSymbol.gitBranch, size: TypeScale.label).foregroundStyle(Color.pBrand)
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
        // 제목("알림 인박스")은 뺐다 — 위 탭 스트립이 이미 "알림"이라 중복. 개수·"모두 지우기"만 남긴다.
        HStack(spacing: 6) {
            Text("놓친 알림 \(state.attention.entries.count)")
                .font(.muxa(.caption)).foregroundStyle(Color.pMuted)
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
                // 사이드바·탭과 **같은 글리프·같은 색**을 쓴다 — 인박스만의 아이콘 표는 없다(StatusStyle이 SSOT).
                // semibold는 선 글리프(checkmark·circle)가 12pt에서 얇아지는 걸 막는다(채운 글리프엔 영향 없음).
                Image(systemName: StatusStyle.glyph(entry.tone))
                    .font(.muxa(.body, weight: .semibold))
                    .foregroundStyle(StatusStyle.color(entry.tone))
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
