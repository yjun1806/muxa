import SwiftUI

/// 푸터 칩 3종(사용량·서비스·백그라운드 터미널)이 공유하는 크롬 — 칩 · 팝오버 셸 · 행 액션 · 안내문.
///
/// 셋은 원래 같은 문법("칩은 요약, 팝오버는 상세")인데 코드는 제각각이었다(폭 240/260, 패딩 xl/lg/md,
/// 헤더 3종, hover 상태 변수 3벌). 같은 문법이면 같은 코드여야 한다 — 여기 한 곳에 모은다.

/// 푸터의 칩(알약) — 요약을 이고 있는 버튼. 누르면 상세 팝오버가 열린다.
///
/// 배경으로 상태를 말한다: 평시(옅음) → hover(진함) → **열림(눌린 상태 유지)**.
/// 열려 있는 동안 눌린 채로 두는 게 중요하다 — 그래야 팝오버가 어디서 나온 창인지 보인다.
struct FooterChip<Label: View>: View {
    @Binding var isOpen: Bool
    let help: String
    @ViewBuilder let label: () -> Label

    @State private var hovered = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            label()
                .padding(.horizontal, Space.sm)
                .frame(height: RowHeight.tight)
                .background(background, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help(help)
    }

    private var background: Color {
        .footerChip(isOpen: isOpen, hovered: hovered)
    }
}

extension Color {
    /// 푸터 칩 배경 — 평시(옅음) → hover(진함) → **열림(눌린 채 유지)**. 열려 있는 동안 눌린 상태를
    /// 유지해야 팝오버가 어느 칩에서 나왔는지 보인다. [[FooterChip]]과 2세그먼트 [[ServiceStrip]]이
    /// 같은 규칙을 써야 한 시스템으로 읽힌다 — 색 판정을 여기 한 곳에 둔다(구조는 각자 다르다).
    static func footerChip(isOpen: Bool, hovered: Bool) -> Color {
        if isOpen { return .pBtnActive }
        return hovered ? .pBtnHover : Color.pBtnHover.opacity(0.5)
    }
}

/// 푸터 팝오버 셸 — [마크 · 제목/보조 · 액세서리] / 구분선 / 내용.
///
/// **셸은 내용에 가로 패딩을 주지 않는다.** 행(`panelRow`)의 hover 배경이 좌우 끝까지 닿아야
/// "이 줄 전체가 버튼"으로 읽히기 때문이다. 인셋은 행·문단이 각자 넣는다(`footerBlock`).
struct FooterPopover<Mark: View, Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let mark: () -> Mark
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HDivider()
            VStack(alignment: .leading, spacing: Space.xs) {
                content()
            }
            .padding(.vertical, Space.md)
        }
        .frame(width: PopoverWidth.footer, alignment: .leading)
        // 표면(배경·모서리·테두리·그림자)은 띄우는 쪽(`floatingPanel()`)이 입힌다 — 커스텀 메뉴와 같은 것.
    }

    /// 제목은 무엇을 보고 있는지, 보조는 그 상태(갱신 시각·개수)를 말한다 — 위계를 크기·색으로 굳힌다.
    private var header: some View {
        HStack(spacing: Space.sm) {
            mark()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.muxa(.title, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                if let subtitle {
                    Text(subtitle)
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                }
            }
            .lineLimit(1)
            Spacer(minLength: Space.md)
            accessory()
        }
        .padding(.horizontal, Space.panelInset)
        .padding(.vertical, Space.sm)
        // 보조 문구가 없어도 헤더가 납작해지지 않게 바닥을 깐다(= 패널 헤더와 같은 높이).
        .frame(minHeight: RowHeight.panelHeader)
    }
}

extension FooterPopover where Accessory == EmptyView {
    /// 헤더 오른쪽에 버튼이 없는 팝오버.
    init(title: String, subtitle: String? = nil,
         @ViewBuilder mark: @escaping () -> Mark,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, mark: mark, accessory: { EmptyView() }, content: content)
    }
}

/// 팝오버 헤더의 출처 마크 — 심볼 하나. (사용량만 `ClaudeMark`를 쓰고 나머지는 이걸 쓴다.)
struct FooterMark: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.muxa(.body))
            .foregroundStyle(Color.pMuted)
            .frame(width: IconSize.mark, height: IconSize.mark)
    }
}

/// 행 끝의 액션 — 아이콘 하나(열기·재시작·종료).
///
/// **파괴적 액션은 색으로 구분한다**(hover 시 danger + 옅은 붉은 배경). 확인 대화상자 없이 즉시
/// 실행되므로, 누르기 직전에 "이건 되돌릴 수 없다"가 보여야 한다 — 색이 그 유일한 경고다.
struct FooterAction: View {
    let icon: String
    let help: String
    var destructive = false
    let action: () -> Void

    @State private var hovered = false

    private var tint: Color { destructive ? .pDanger : Color(nsColor: Palette.mutedHover) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.muxa(.label))
                .foregroundStyle(hovered ? tint : Color.pMuted)
                // 아이콘(11pt)만으로는 과녁이 너무 작다 — 행 높이 한 단(22)의 정사각형을 준다.
                .frame(width: RowHeight.tight, height: RowHeight.tight)
                .background(hovered ? tint.opacity(Tint.subtle) : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovered = $0 }
        .animation(Motion.fast, value: hovered)
        .help(help)
    }
}

/// 목록이 비었을 때의 안내 — [무엇이 없다] + [왜/무엇을 하면 되는지] + 그 자리에서 할 수 있는 행동.
struct FooterHint<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.tight) {
                Text(title)
                    .font(.muxa(.label, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                Text(detail)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action()
        }
        .footerBlock()
    }
}

extension FooterHint where Action == EmptyView {
    init(title: String, detail: String) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

extension View {
    /// 팝오버 안의 **행이 아닌** 덩어리(문단·막대·안내문)에 주는 가로 인셋 — 행과 같은 선에 맞춘다.
    func footerBlock() -> some View {
        padding(.horizontal, Space.panelInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
