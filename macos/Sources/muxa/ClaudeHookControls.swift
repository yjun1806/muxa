import SwiftUI

/// 설정 패널의 Claude 훅 관리 — 상태 표시 + 설치/제거.
///
/// 원래 주의 인박스 푸터에 있던 걸 여기로 옮겼다. 역할이 갈린다: **미설치 유도**는 전역 푸터
/// (`HookInstallChip`, 눈에 띄고 설치되면 사라짐), **상태·제거 같은 관리**는 여기(드문 고급 동작).
/// 훅이 있어야 알림·에이전트 상태·A-1 사용량 추적이 정확하다 — "설치됨"과 "동작 중"을 구분해
/// 정직하게 드러낸다(settings.json에 썼다는 것과 훅이 실제 발화하는 것은 다르다).
struct ClaudeHookControls: View {
    let state: AppState

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icon).font(.muxa(.label)).foregroundStyle(Color(nsColor: tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(state.hookStatus.label).font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1)
                Text("알림·에이전트 상태·사용량 추적").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            Spacer(minLength: Space.sm)
            if state.needsHookInstall {
                Button { state.installClaudeHooks() } label: {
                    Text("설치").font(.muxa(.label, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pBrand)
                .help("~/.claude/settings.json에 muxa 훅·상태줄을 설치한다(기존 설정 보존, 백업 생성)")
            } else {
                Button { state.uninstallClaudeHooks() } label: {
                    Text("제거").font(.muxa(.label))
                }
                .buttonStyle(.plain).foregroundStyle(Color.pMuted)
                .help("settings.json에서 muxa 훅·상태줄만 제거한다(다른 설정은 그대로, 사용자 statusLine 복원)")
            }
        }
        .padding(.horizontal, Space.panelInset)
    }

    private var icon: String {
        switch state.hookStatus {
        case .verified: return "bolt.fill"
        case .installed: return "bolt"
        case .notInstalled: return "bolt.slash"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: NSColor {
        switch state.hookStatus {
        case .verified: return Palette.gitAdded
        case .installed: return Palette.borderActivity
        case .notInstalled: return Palette.muted
        case .failed: return Palette.gitDeleted
        }
    }
}
