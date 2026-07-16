import SwiftUI

/// 워크트리 프로젝트 상단 **링크 카드** — 이 워크트리에서 도는 작업이 다른 프로젝트의 탭에 갇혀 있을 때 뜬다(D31).
///
/// 에이전트가 옛 탭 안에서 `git worktree add` 후 `cd`하면 살아있는 세션이 옛 탭에 남는다 — 그 탭으로 이어준다.
/// **가서 보기**는 그 탭으로 점프(`focusAgentTab`), **가져오기**는 영속(∞) 세션만 이 프로젝트로 이식한다
/// (일반 터미널은 프로세스가 로컬 서피스에 묶여 옮길 수 없다 → 버튼을 아예 안 준다). 대상이 없으면 아무것도 안 그린다.
struct WorktreeLinkBanner: View {
    let state: AppState
    let project: Project

    var body: some View {
        if let link = state.externalLiveSession(for: project.id) {
            HStack(spacing: Space.sm) {
                Image(systemName: "arrow.turn.up.right").font(.muxa(.caption)).foregroundStyle(Color.pBrand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("이 워크트리의 작업이 다른 탭에서 진행 중")
                        .font(.muxa(.caption, weight: .semibold)).foregroundStyle(Color.pFg)
                    Text(link.isPersistent ? "지속 세션 — 이 프로젝트로 가져올 수 있습니다"
                                           : "일반 터미널 — 가서 볼 수만 있습니다(가져오기 불가)")
                        .font(.muxa(.micro)).foregroundStyle(Color.pMuted)
                }
                Spacer(minLength: Space.sm)
                Button { state.focusAgentTab(link.originProjectId, link.tabId) } label: {
                    Text("가서 보기").font(.muxa(.caption, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pBrand).clickCursor()
                .help("작업이 도는 원본 탭으로 이동합니다")
                if link.isPersistent {
                    Button { state.bringPersistentTab(from: link.originProjectId, tabId: link.tabId, to: project.id) } label: {
                        Text("가져오기").font(.muxa(.caption, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.pBrand).clickCursor()
                    .help("지속 세션을 이 프로젝트의 새 탭으로 가져옵니다(안에서 돌던 작업 그대로)")
                }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder))
            .padding(.top, Space.sm).padding(.horizontal, Space.sm)
        }
    }
}
