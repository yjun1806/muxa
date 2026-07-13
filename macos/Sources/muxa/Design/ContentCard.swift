import SwiftUI

/// 콘텐츠 카드(터미널·패널이 사는 판)의 좌표계와 크기를 아래로 흘려보내는 통로.
///
/// 칸 강조 테두리가 "내가 카드의 어느 모서리에 닿아 있나"를 알아야 그 코너만 둥글릴 수 있다.
/// 닿지 않는 코너까지 둥글리면 분할 경계에서 테두리가 괜히 둥글게 패인다.
enum ContentCard {
    /// 칸이 자기 위치를 카드 기준으로 잴 때 쓰는 좌표계 이름.
    static let space = "muxa.contentCard"
    /// 모서리에 "닿았다"고 볼 오차.
    ///
    /// 칸의 끝은 카드 경계와 정확히 일치하지 않는다 — 분할선 두께·테두리·반올림이 몇 pt를 먹는다.
    /// 오차를 너무 빡빡하게 잡으면 실제로 모서리에 닿은 칸이 "안 닿았다"고 판정돼 직각으로 그려지고,
    /// 그 직각 모서리가 카드의 라운드 클립에 잘려 나간다(테두리가 끊겨 보이는 증상).
    /// 반대로 넉넉히 잡아도 오판이 없다 — 내부 분할 칸은 최소 칸 크기(수십 pt)만큼 떨어져 있다.
    static let touchTolerance: CGFloat = 8
}

private struct ContentCardSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// 콘텐츠 카드의 크기. `.zero`면 아직 모른다는 뜻(그 경우 모든 코너를 둥글리는 쪽으로 폴백).
    var contentCardSize: CGSize {
        get { self[ContentCardSizeKey.self] }
        set { self[ContentCardSizeKey.self] = newValue }
    }
}

/// 카드 크기를 레이아웃 패스에서 위로 올려보내는 통로.
/// (`GeometryReader` 안에서 `@State`를 직접 쓰면 렌더 도중 상태를 바꾸는 셈이라 경고·갱신 루프가 난다.)
private struct ContentCardSizePreference: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// 이 뷰를 콘텐츠 카드로 삼는다 — 아래 칸들이 자기 위치·카드 크기를 알 수 있게 된다.
    /// 크기는 `onCardSize`로 돌려주므로 호출자가 상태에 담아 다시 `size`로 넣어준다.
    func contentCardSpace(size: CGSize, onCardSize: @escaping (CGSize) -> Void) -> some View {
        coordinateSpace(name: ContentCard.space)
            .environment(\.contentCardSize, size)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentCardSizePreference.self, value: geo.size)
                }
            )
            .onPreferenceChange(ContentCardSizePreference.self, perform: onCardSize)
    }
}
