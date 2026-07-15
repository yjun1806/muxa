import Bonsplit
import SwiftUI

/// ∞ 지속 세션 탭을 **안에서 작업이 도는 중에** 닫으려 할 때, 그 칸 상단에 얹는 확인 배너.
///
/// 예전엔 `NSAlert`(앱 전역 모달)로 물었는데, 앱 아이콘이 크게 뜨는 그 모양이 "탭이 아니라 앱을 닫는다"는
/// 인상을 줬다. 세션 재개 배너(§ResumeOverlay)와 같은 방식으로 **이 칸에서만** 조용히 묻는다.
/// 상태는 store가 소유(closeConfirmations)하고, 이 뷰는 렌더·위임만 한다(상태는 위, 표현은 아래).
struct CloseConfirmOverlay: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        // closeConfirmation(관측)이 채워지면 배너가 뜨고, 버튼이 소비하면 사라진다.
        // ZStack에 애니메이션을 걸어야 배너의 transition(등장/퇴장)이 발동한다(§paneBannerTransition).
        ZStack {
            if let work = store.closeConfirmation(for: tabId) {
                CloseConfirmBanner(
                    work: work,
                    onKeep: { store.confirmCloseKeeping(tabId) },
                    onKill: { store.confirmCloseKilling(tabId) },
                    onCancel: { store.cancelClose(tabId) }
                )
                .padding(.top, Space.md)
                .paneBannerTransition()
            }
        }
        .animation(Motion.medium, value: store.closeConfirmation(for: tabId))
    }
}

/// 확인 배너 본체(순수 프레젠테이션) — 실행 중인 작업 이름 + 유지/종료/취소 버튼. store를 모른다(콜백만 받는다).
private struct CloseConfirmBanner: View {
    let work: String
    let onKeep: () -> Void
    let onKill: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "infinity")
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted)
            // 무엇을 닫는지 — 실행 중인 작업 이름을 앞세운다.
            Text("‘\(work)’ 실행 중 — 닫을까요?")
                .font(.muxa(.body, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            // 단축키는 배너가 떠 있을 때만 이벤트 게이트(§AppState.closeConfirmShortcut)가 처리한다 —
            // 터미널이 firstResponder라 SwiftUI .keyboardShortcut은 불안정해 여기선 힌트만 노출한다.

            // 1급 CTA(안전) — 실수로 눌러도 돌던 작업을 지키는 ‘유지’. ⌘B.
            Button(action: onKeep) {
                HStack(spacing: 5) {
                    Text("백그라운드로 유지")
                    ShortcutCap("⌘B", tint: Color.pOnBrand.opacity(0.65))
                }
                .font(.muxa(.body, weight: .medium))
                .paneBannerCTA()
            }
            .buttonStyle(.plain)
            .clickCursor()

            // 파괴적 — 지금 돌던 작업이 사라진다. danger 색으로 구별한다. ⌘W(배너가 떴을 때 한 번 더).
            Button(action: onKill) {
                HStack(spacing: 5) {
                    Text("완전 종료")
                    ShortcutCap("⌘W", tint: Color.pDanger.opacity(0.7))
                }
                .font(.muxa(.body, weight: .medium))
                .foregroundStyle(Color.pDanger)
                .padding(.horizontal, Space.panelInset).padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Color.pDanger.opacity(0.5), lineWidth: RowHeight.hairline))
            }
            .buttonStyle(.plain)
            .clickCursor()

            // esc 또는 ⌘C. 관용적인 esc를 힌트로 노출한다.
            Button(action: onCancel) {
                HStack(spacing: 5) {
                    Text("취소")
                    ShortcutCap("esc", tint: Color.pMuted)
                }
                .font(.muxa(.body))
                .foregroundStyle(Color.pMuted)
                .padding(.horizontal, Space.md).padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .clickCursor()
        }
        .paneBannerChrome(maxWidth: 600)
    }
}

/// 버튼 안에 얹는 단축키 힌트 — 작은 mono 텍스트. 키캡 박스는 배너가 이미 좁아 생략하고 색만 옅게 준다.
private struct ShortcutCap: View {
    let keys: String
    let tint: Color

    init(_ keys: String, tint: Color) {
        self.keys = keys
        self.tint = tint
    }

    var body: some View {
        Text(keys)
            .font(.muxaMono(.label))
            .foregroundStyle(tint)
    }
}
