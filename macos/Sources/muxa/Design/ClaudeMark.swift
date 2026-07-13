import SwiftUI
import AppKit

/// Claude 심볼 — 사용량이 어느 서비스 것인지 알리는 출처 마크.
///
/// 공식 SVG(`Resources/claude-symbol.svg`)를 그대로 쓴다. NSImage가 SVG를 벡터로 렌더하므로
/// 크기를 키워도 안 뭉개진다(파일 아이콘이 쓰는 것과 같은 경로 — `IconTheme`).
/// 색은 원본 그대로(Claude 주황) 둔다 — 로고라 임의로 물들이지 않는다.
struct ClaudeMark: View {
    var size: CGFloat = 12

    var body: some View {
        if let image = Self.symbol {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel("Claude")
        }
    }

    /// 번들에서 1회 로드해 재사용(뷰가 그려질 때마다 디스크를 읽지 않게).
    /// 리소스가 없으면 nil — 마크만 안 뜨고 사용량 표시는 정상 동작한다.
    private static let symbol: NSImage? = {
        guard let url = Bundle.module.url(forResource: "claude-symbol", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false // 원본 색(주황)을 유지 — 템플릿이면 시스템이 단색으로 덮는다
        return image
    }()
}
