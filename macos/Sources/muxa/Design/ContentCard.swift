import SwiftUI

/// 콘텐츠 카드(터미널·패널이 사는 판)와, 그 위에 그려지는 **칸 강조 테두리 레이어**.
///
/// 칸 테두리를 칸 안에서 그리면 카드의 라운드 클립에 반드시 깎인다 — 테두리 곡선과 클립 곡선을
/// 아무리 맞춰도 칸이 카드 경계에서 1pt만 안쪽에 있으면 곡선이 어긋나 모서리가 잘린다.
/// 그래서 **테두리를 클립 바깥에서 그린다**: 칸은 자기 위치와 색만 preference로 올려보내고,
/// 실제 그리기는 카드를 클립한 *다음에* 얹는 레이어가 한다. 클립이 닿을 수 없으니 안 깎인다.
///
/// 위치는 **전역(창) 좌표**로 주고받는다. Bonsplit은 터미널 콘텐츠를 portal로 호스팅해서
/// 카드가 그 뷰의 SwiftUI 조상이 아닐 수 있고, 그러면 이름 붙인 좌표계(`.named`)는 엉뚱한 값을 준다.
/// 전역 좌표는 계층과 무관하게 성립하므로 레이어가 자기 전역 위치를 빼서 카드 기준으로 되돌린다.
///
/// 카드 모서리에 닿은 칸은 그 변을 카드 경계까지 스냅해 카드와 같은 반경으로 둥글린다 —
/// 여백도, 잘림도 없이 카드 테두리 자리에 정확히 겹쳐 그려진다.
enum ContentCard {
    /// 모서리에 "닿았다"고 볼 오차 — 분할선 두께·테두리·반올림이 몇 pt를 먹는다.
    ///
    /// **판정만 하는 값이 아니라 실제로 좌표를 옮기는 값이다**(닿았다고 보면 그 변을 카드 경계까지 스냅한다).
    /// 즉 이 거리 안에 있는 칸의 테두리는 최대 이만큼 바깥으로 끌려간다. 그래도 안전한 이유는
    /// 카드 안에 붙는 것들이 전부 이보다 훨씬 두껍기 때문이다 — 도구 패널 최소 폭이 180/300pt로
    /// 강제돼 있고(`AppState.panelWidthRange`·`gitPanelWidthRange`), 내부 분할 칸도 최소 칸 크기만큼 떨어져 있다.
    static let touchTolerance: CGFloat = 8
}

/// 칸 하나가 요청한 테두리 한 겹. 색이 nil이면 "지금은 안 보임"(칸이 그대로면 뷰는 남아 색만 페이드된다).
/// 칸 자체가 사라지면(탭 전환·칸 닫기) spec이 목록에서 빠져 뷰도 함께 사라진다 — 그땐 페이드가 없다.
/// Equatable이라 레이아웃 패스(리사이즈·분할선 드래그)마다 오는 동일한 preference는 SwiftUI가 걸러낸다.
struct PaneBorderSpec: Identifiable, Equatable {
    let id: String
    /// 칸의 전역(창) 좌표 프레임.
    let globalRect: CGRect
    let color: Color?
    let lineWidth: CGFloat
    let animation: Animation
}

/// 칸들이 올려보낸 테두리 요청을 모으는 통로.
struct PaneBorderPreference: PreferenceKey {
    static let defaultValue: [PaneBorderSpec] = []
    static func reduce(value: inout [PaneBorderSpec], nextValue: () -> [PaneBorderSpec]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// 이 칸의 테두리 한 겹을 카드 레이어에 올려보낸다(직접 그리지 않는다 — 클립에 깎이므로).
    func paneBorder(id: String, color: Color?, lineWidth: CGFloat = 2, animation: Animation) -> some View {
        overlay {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PaneBorderPreference.self,
                    value: [PaneBorderSpec(
                        id: id, globalRect: geo.frame(in: .global),
                        color: color, lineWidth: lineWidth, animation: animation
                    )]
                )
            }
            .allowsHitTesting(false)
        }
    }

    /// 이 뷰를 콘텐츠 카드로 삼는다 — 라운드 클립 → 카드 테두리 → 칸 테두리 순으로 쌓는다.
    /// (칸 테두리가 맨 위라, 카드 모서리에 닿은 칸은 카드 테두리를 덮으며 이어진다.)
    func contentCard(radius: CGFloat, border: Color) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
            .overlayPreferenceValue(PaneBorderPreference.self) { specs in
                GeometryReader { geo in
                    let card = geo.frame(in: .global)
                    ForEach(specs) { spec in
                        PaneBorderShape(spec: spec, card: card, radius: radius)
                    }
                }
                // 테두리는 칸을 따라 **순간이동**해야 한다. 이 레이어는 Bonsplit이 칸 콘텐츠에 쳐둔
                // 애니메이션 차단막 바깥이라, 상위의 살아있는 애니메이션(사이드바 peek·탭 전환·프로젝트 전환)이
                // 그대로 스며들면 콘텐츠는 즉시 옮겨간 자리로 테두리만 미끄러져 따라온다.
                // 색 전환은 아래 PaneBorderShape가 명시적으로 다시 켠다.
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)
            }
    }
}

/// 칸 테두리 한 겹을 카드 위에 그린다 — 카드 모서리에 닿은 변은 경계까지 스냅하고 그 코너만 둥글린다.
private struct PaneBorderShape: View {
    let spec: PaneBorderSpec
    /// 카드의 전역 프레임 — 칸의 전역 좌표를 카드 기준으로 되돌리는 원점이자, 닿음 판정의 경계.
    let card: CGRect
    let radius: CGFloat

    var body: some View {
        let t = ContentCard.touchTolerance
        let r = spec.globalRect
        let left = r.minX <= card.minX + t
        let top = r.minY <= card.minY + t
        let right = r.maxX >= card.maxX - t
        let bottom = r.maxY >= card.maxY - t

        // 닿은 변은 카드 경계에 붙인다 — 테두리와 카드 사이에 어중간한 틈이 남지 않는다.
        // 좌표는 카드 원점 기준(레이어의 로컬 좌표)으로 되돌린다.
        let minX = (left ? card.minX : r.minX) - card.minX
        let minY = (top ? card.minY : r.minY) - card.minY
        let maxX = (right ? card.maxX : r.maxX) - card.minX
        let maxY = (bottom ? card.maxY : r.maxY) - card.minY
        let rect = CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))

        UnevenRoundedRectangle(
            topLeadingRadius: left && top ? radius : 0,
            bottomLeadingRadius: left && bottom ? radius : 0,
            bottomTrailingRadius: right && bottom ? radius : 0,
            topTrailingRadius: right && top ? radius : 0
        )
        .strokeBorder(spec.color ?? .clear, lineWidth: spec.lineWidth)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .animation(spec.animation, value: spec.color)
    }
}
