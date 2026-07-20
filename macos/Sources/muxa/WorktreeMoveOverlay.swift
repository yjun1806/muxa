import Bonsplit
import SwiftUI

/// 진행 중인 세션(∞ 탭)이 **다른 프로젝트의 워크트리** 안에서 작업 중일 때, 그 칸 상단에 얹는 이동 배너
/// (D31 이동 배지의 원본 쪽 실현 — 워크트리 쪽은 링크 탭이 맡는다).
///
/// 영속(∞) 탭에만 뜬다(판정 자체가 그렇다 — 일반 터미널은 프로세스가 서피스에 묶여 못 옮긴다).
/// "여기 둠"으로 무시하면 같은 대상으로는 다시 조르지 않는다(`dismissedMove` — 다른 워크트리로 가면 다시 뜬다).
/// 판정·실행은 스토어에 꽂힌 위임(`moveSuggestion`/`onWorktreeMove`)으로 AppState가 맡는다.
struct WorktreeMoveOverlay: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        ZStack {
            if let s = store.moveSuggestion?(tabId), store.dismissedMove[tabId] != s.targetProjectId {
                WorktreeMoveBanner(
                    targetName: s.targetName,
                    onMove: { store.onWorktreeMove?(tabId, s.targetProjectId) },
                    onDismiss: { store.dismissMoveSuggestion(tabId, targetId: s.targetProjectId) }
                )
                .padding(.top, Space.md)
                .paneBannerTransition()
            }
        }
        // 등장(제안 도착)과 퇴장(무시·이동) 모두 transition이 발동하도록 두 축을 다 바인딩한다.
        .animation(Motion.medium, value: store.moveSuggestion?(tabId) != nil)
        .animation(Motion.medium, value: store.dismissedMove[tabId])
    }
}

/// 배너 본체(순수 프레젠테이션) — 대상 프로젝트 이름 + 옮기기/여기 둠. store를 모른다(콜백만 받는다).
private struct WorktreeMoveBanner: View {
    let targetName: String
    let onMove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MuxaIcon(name: MuxaSymbol.gitBranch, size: TypeScale.caption)
                .foregroundStyle(Color.pMuted)
            Text("이 세션은 ‘\(targetName)’ 워크트리에서 작업 중")
                .font(.muxa(.body, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            // 1급 CTA — 세션(tmux)을 그 프로젝트의 탭으로 이식한다(작업은 끊기지 않는다).
            Button(action: onMove) {
                Text("프로젝트로 옮기기")
                    .font(.muxa(.body, weight: .medium))
                    .paneBannerCTA()
            }
            .buttonStyle(.plain)
            .clickCursor()
            .help("이 ∞ 세션을 ‘\(targetName)’ 프로젝트의 탭으로 옮깁니다(돌던 작업 그대로)")

            Button(action: onDismiss) {
                Text("여기 두기")
                    .font(.muxa(.body))
                    .foregroundStyle(Color.pMuted)
                    .padding(.horizontal, Space.md).padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .clickCursor()
            // 약속은 지킬 수 있는 만큼만 — 무시 상태는 세션 한정(영속 안 함)이라 "이 세션 동안"으로 정직하게.
            // 되돌릴 길(링크 탭의 가져오기)도 알려줘 "영구 결정"처럼 느껴지지 않게 한다.
            .help("이 세션 동안은 다시 묻지 않습니다 — 필요하면 워크트리 프로젝트의 링크 탭에서 가져올 수 있습니다")
        }
        .paneBannerChrome(maxWidth: 560)
    }
}
