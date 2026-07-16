import Bonsplit
import SwiftUI

/// 링크 탭의 액션 — 프로젝트를 넘나드는 실행(점프·이식)은 AppState가 맡는다(스토어에 위임으로 꽂힘).
enum WorktreeLinkAction {
    case go    // 가서 보기 — 작업이 도는 원본 탭으로 점프
    case bring // 가져오기 — 영속(∞ tmux) 세션을 이 프로젝트로 이식
}

/// 워크트리 **링크 탭**의 본문 — "이 워크트리의 작업이 다른 프로젝트의 탭에서 진행 중"을 알리는 정보 화면(D31).
///
/// 에이전트가 옛 탭 안에서 워크트리를 만들고 들어가면, 자동 승격된 워크트리 프로젝트의 첫 화면이 이 탭이다
/// (터미널이 아니다 — 셸을 띄우지 않는다). 대상·액션은 스토어에 꽂힌 위임(`worktreeLink`/`onWorktreeLinkAction`)을
/// 통해 AppState가 맡는다 — 스토어·이 뷰는 다른 프로젝트의 탭을 모른다.
///
/// **가서 보기** = 원본 탭 점프(탭 유지 — 돌아올 수 있다). **가져오기** = 영속(∞ tmux) 세션만 — 이식되면
/// `bringPersistentTab`이 이 스토어의 링크 탭을 일괄 정리한다(안내가 소임을 다했다).
/// 일반 터미널은 프로세스가 로컬 서피스에 묶여 못 옮긴다.
struct WorktreeLinkPane: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        Group {
            if let link = store.worktreeLink?() {
                linked(link)
            } else {
                // 대상이 사라졌다(원본 탭 닫힘·이미 가져옴) — 빈 프로젝트 뷰와 같은 문법으로 다음 행동을 준다.
                EmptyState(icon: "arrow.triangle.branch", title: "연결된 작업이 없습니다") {
                    openTerminalButton
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }

    private func linked(_ link: ExternalWorktreeSession) -> some View {
        EmptyState(icon: "arrow.triangle.branch", title: "이 워크트리의 작업이 다른 탭에서 진행 중") {
            Text(link.isPersistent ? "지속 세션(∞) — 이 프로젝트로 가져올 수 있습니다"
                                   : "일반 터미널 — 가서 볼 수만 있습니다(가져오기 불가)")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
            HStack(spacing: Space.md) {
                actionButton("가서 보기", icon: "arrow.up.right") {
                    store.onWorktreeLinkAction?(link, .go)
                }
                .help("작업이 도는 원본 탭으로 이동합니다")
                if link.isPersistent {
                    actionButton("가져오기", icon: "square.and.arrow.down") {
                        // 링크 탭 정리는 이식 쪽(`bringPersistentTab` → `closeWorktreeLinkTabs`)이 맡는다 — 단일 메커니즘.
                        store.onWorktreeLinkAction?(link, .bring)
                    }
                    .help("지속 세션을 이 프로젝트의 새 탭으로 가져옵니다(안에서 돌던 작업 그대로)")
                }
            }
        }
    }

    /// EmptyProjectView의 버튼과 같은 문법 — 정보 화면의 주 동작 버튼.
    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.muxa(.title))
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(Color.pBtnHover, in: RoundedRectangle(cornerRadius: Radius.sm))
                .foregroundStyle(Color.pFg)
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private var openTerminalButton: some View {
        actionButton("새 터미널", icon: "plus") {
            store.newTerminal()
            _ = store.controller.closeTab(tabId) // 안내 탭은 치운다 — 이제 일반 프로젝트로 쓰는 것
        }
    }
}
