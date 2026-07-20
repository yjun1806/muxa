import SwiftUI

/// Git 패널 헤더 — 브랜치·동기화 카운터·PR 배지·pull/push/새로고침.
/// 상태를 소유하지 않는다(controlled) — 값과 클로저만 받는다.
struct GitPanelHeader: View {
    let status: GitStatus?
    let branches: [String]
    let gh: GitService.GHStatus?
    let syncBusy: Bool
    let dir: String?

    var onCheckout: (String) -> Void
    var onPull: () -> Void
    var onPush: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            MuxaIcon(name: MuxaSymbol.gitBranch)
                .font(.muxa(.body))
                .foregroundStyle(Color.pMuted)
                // 폰트 크기만으로 세우면 브랜치명 길이가 바뀔 때 광학 중심이 흔들린다.
                .frame(width: IconSize.inlineMark, height: IconSize.inlineMark)

            branchLabel

            if let status {
                if status.ahead > 0 { counter("arrow.up", status.ahead, label: "푸시 안 된 커밋") }
                if status.behind > 0 { counter("arrow.down", status.behind, label: "받아올 커밋") }
            }
            if let gh { GitPRBadge(gh: gh, dir: dir) }

            Spacer(minLength: Space.xs)

            if status != nil {
                if syncBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
                } else {
                    IconButton(icon: "arrow.down.to.line", help: "Pull", action: onPull)
                    IconButton(icon: "arrow.up.to.line", help: "Push", action: onPush)
                }
            }
            IconButton(icon: "arrow.clockwise", help: "새로고침", action: onRefresh)
        }
        .panelBar(height: RowHeight.panelHeader)
    }

    /// 브랜치명 — git 저장소면 로컬 브랜치 전환 메뉴, 아니면 "Git" 라벨.
    @ViewBuilder
    private var branchLabel: some View {
        if let status, !branches.isEmpty {
            Menu {
                ForEach(branches, id: \.self) { b in
                    Button { onCheckout(b) } label: {
                        if b == status.branch { Label(b, systemImage: "checkmark") } else { Text(b) }
                    }
                    .disabled(b == status.branch)
                }
            } label: {
                Text(status.branch)
                    .font(.muxa(.body, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(syncBusy)
            .accessibilityLabel("브랜치 \(status.branch), 눌러서 전환")
        } else {
            Text(status?.branch ?? "Git")
                .font(.muxa(.body, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
        }
    }

    private func counter(_ icon: String, _ n: Int, label: String) -> some View {
        HStack(spacing: Space.tight) {
            Image(systemName: icon).font(.muxa(.micro))
            Text("\(n)").font(.muxaMono(.label))
        }
        .foregroundStyle(Color.pMuted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(n)개")
    }
}

/// GitHub PR 배지 — `#번호 + PR 상태색` 알약, CI 롤업은 **알약 밖** 독립 글리프.
///
/// **CI를 알약에 넣지 않는다.** `Pill`은 "색 하나만 정하면 배경 틴트가 따라온다"는 컴포넌트다.
/// 초록 틴트 알약 안에 빨간 CI 실패 아이콘을 넣으면 알약이 "OPEN"이라 말하는 동안 내용물이
/// "실패"라 말한다 — 두 색이 싸우고 규칙이 깨진다. PR 상태와 CI는 다른 축이라 분리한다.
struct GitPRBadge: View {
    let gh: GitService.GHStatus
    let dir: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            Button {
                if let dir { Task { await GitService.ghOpenPR(in: dir) } }
            } label: {
                Pill(color: PRStatusStyle.color(gh.state)) {
                    Image(systemName: PRStatusStyle.icon).font(.muxa(.micro))
                    Text("#\(gh.prNumber)").font(.muxaMono(.caption, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help(help)
            .accessibilityLabel("PR \(gh.prNumber)번, \(PRStatusStyle.label(gh.state)). 눌러서 브라우저로 열기")

            if let rollup = gh.rollup {
                Image(systemName: PRStatusStyle.checkGlyph(rollup))
                    .font(.muxa(.micro, weight: .bold))
                    .foregroundStyle(PRStatusStyle.checkColor(rollup))
                    .accessibilityLabel(PRStatusStyle.checkLabel(rollup))
            }
        }
    }

    private var help: String {
        var s = "PR #\(gh.prNumber) · \(gh.state)"
        if gh.rollup != nil {
            s += " · CI 통과 \(gh.passing)"
            if gh.failing > 0 { s += " 실패 \(gh.failing)" }
            if gh.pending > 0 { s += " 진행 \(gh.pending)" }
        }
        return s
    }
}
