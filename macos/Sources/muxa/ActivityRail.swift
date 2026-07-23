import SwiftUI

/// 우측 far-right에 **상시** 붙는 최소 폭 세로 레일 — 도구 슬롯(탐색기·Git·알림·설정)의 직접 진입점.
///
/// 왜: 예전엔 상단바 `sidebar.right` 단일 토글로 인스펙터를 열고, 그 안 탭 스트립에서 다시 골라야 했다
/// (열리는 건 늘 "마지막 탭"). 레일은 패널이 닫혀 있어도 아이콘·알림 배지를 늘 보여주고 **1클릭에** 연다.
/// 슬롯 통합(폭·상태·keep-alive)·상태 API는 그대로 두고 **진입점만** 여기로 모았다.
///
/// 3구역: ① 슬롯 스위처(탐색기·Git·알림) ② 액션(스크래치 창 — 토글 아님) ③ 전역(설정, 최하단).
struct ActivityRail: View {
    let state: AppState

    var body: some View {
        VStack(spacing: Space.sm) {
            // ① 슬롯 스위처 — 우측 패널 토글(같은 걸 다시 누르면 닫힘)
            RailButton(icon: "folder", help: "탐색기", active: state.showExplorer) {
                state.selectInspector(.explorer)
            }
            RailButton(icon: MuxaSymbol.gitBranch, help: "Git", active: state.showGitPanel) {
                state.selectInspector(.git)
            }
            RailButton(icon: "bell", help: "알림 인박스", active: state.showAttention,
                       badge: state.attentionBadgeCount) {
                state.selectInspector(.attention)
                if state.showAttention { state.attention.markAllRead() } // 여는 즉시 읽음(표준 인박스 UX)
            }

            RailDivider()

            // ② 액션 — 워크스페이스와 무관한 스크래치 터미널 창(우측 슬롯이 아니라 새 창이라 여기서 가른다)
            RailButton(icon: "terminal", help: "스크래치 터미널 (⌘⌥T)", active: false) {
                state.openScratchWindow()
            }

            Spacer(minLength: 0)

            RailDivider()

            // ③ 전역 슬롯 — 설정은 자주 안 봐서 맨 아래로(우측 슬롯을 인스펙터와 상호배타로 공유)
            RailButton(icon: "gearshape", help: "설정", active: state.showSettings) {
                state.toggleSettings()
            }
        }
        .padding(.vertical, Space.md)
        .frame(width: Rail.width)
        .frame(maxHeight: .infinity)
        .background(Color.pPanel)
        .overlay(alignment: .leading) {
            // 좌측 경계 — 닫힌 rightSlot에선 콘텐츠 카드와, 열렸을 땐 패널과 레일을 가른다.
            Rectangle().fill(Color.pBorder).frame(width: RowHeight.hairline)
        }
    }
}

/// 레일 항목 버튼 — 아이콘 하나 + (옵션) 알림 배지. 활성 표시는 **fill 승격이 아니라** 배경 + 좌측
/// 브랜드 인셋 바로 통일한다. git 글리프가 커스텀 SVG라 `.fill` variant가 없어, 공통 스타일로 줘야
/// SF·커스텀 5글리프가 한 계열로 균질해진다(사용자 요청: 아이콘 통일).
private struct RailButton: View {
    let icon: String
    let help: String
    let active: Bool
    var badge: Int = 0
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            MuxaIcon(name: icon, size: Rail.icon)
                .foregroundStyle(iconColor)
                .frame(width: IconSize.control, height: IconSize.control)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pBtnActive)
                    }
                }
                .overlay(alignment: .leading) {
                    if active {
                        Capsule().fill(Color.pBrand)
                            .frame(width: Rail.markBar, height: Rail.icon)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { badgeView }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .muxaTip(help) // 앱 표준 툴팁(0.5s, 앵커 옆 칩) — 시스템 NSToolTip은 지연이 길어 안 뜨는 듯했다
        .accessibilityLabel(help)
    }

    /// 활성이면 전경색, 아니면 muted(hover에서 진해진다) — IconButton과 같은 규칙.
    private var iconColor: Color {
        if active { return Color.pFg }
        return hovered ? Color(nsColor: Palette.mutedHover) : Color.pMuted
    }

    /// 알림 숫자 배지 — 아이콘 밖으로 걸치는 앰버 알약(`AttentionBell`과 같은 조판).
    private var badgeView: some View {
        Text(badge > 99 ? "99+" : "\(badge)")
            .font(.muxaMono(.nano, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 12)
            .frame(height: 12)
            .background(Color(nsColor: Palette.borderActivity), in: Capsule())
            .fixedSize()
            .offset(x: 4, y: -2)
    }
}

/// 레일 구역 구분선 — 폭 안에 갇힌 짧은 가로선(슬롯 스위처 ↔ 액션 ↔ 설정을 가른다).
private struct RailDivider: View {
    var body: some View {
        Rectangle().fill(Color.pBorder)
            .frame(height: RowHeight.hairline)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.tight)
    }
}
