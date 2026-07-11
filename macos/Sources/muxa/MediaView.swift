import AppKit
import AVKit
import SwiftUI

/// 이미지 파일 뷰어 탭 — 비율 유지로 맞춰 표시하고 애니메이션 GIF도 재생한다(NSImageView).
/// CodeView·MarkdownView와 같은 뷰어 셸 패턴(헤더 옵션 + pBg 배경).
struct ImageFileView: View {
    let target: FileViewTarget
    var chrome: Bool = true // 그룹 서브탭 안에서는 서브탭 바가 헤더 역할이라 자체 헤더를 숨긴다
    var onClose: () -> Void

    /// 이미지 원본 크기(pt). 이보다 크게 확대하지 않도록 프레임 상한으로 쓴다.
    @State private var natural: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                ViewerHeader(icon: target.tabIcon, title: target.path, onClose: onClose)
                Rectangle().fill(Color.pBorder).frame(height: 1)
            }
            // 원본 크기를 넘겨 확대하지 않고(작은 이미지는 그대로), 창보다 크면 여백을 두고 축소.
            ScalingImageView(path: target.path)
                .frame(maxWidth: natural?.width ?? .infinity, maxHeight: natural?.height ?? .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // 남는 공간은 가운데 정렬
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: target.id) {
            natural = NSImage(contentsOfFile: target.path).map { size in
                CGSize(width: size.size.width, height: size.size.height)
            }
        }
    }
}

/// NSImageView 래퍼 — 비율 유지 축소, GIF 애니메이션 재생. 경로가 바뀔 때만 다시 로드한다.
private struct ScalingImageView: NSViewRepresentable {
    let path: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FittingImageView {
        let v = FittingImageView()
        v.imageScaling = .scaleProportionallyDown // 큰 이미지는 맞춰 축소, 작은 건 원본 크기(확대 안 함)
        v.imageAlignment = .alignCenter
        v.animates = true // 애니메이션 GIF
        reload(v, context.coordinator)
        return v
    }

    func updateNSView(_ v: FittingImageView, context: Context) {
        // SwiftUI 갱신마다 디스크를 다시 읽지 않게 경로 변경 시에만 로드.
        guard context.coordinator.path != path else { return }
        reload(v, context.coordinator)
    }

    private func reload(_ v: FittingImageView, _ coord: Coordinator) {
        coord.path = path
        v.image = NSImage(contentsOfFile: path)
    }

    final class Coordinator { var path: String? }
}

/// intrinsicContentSize를 무력화한 NSImageView. 기본 NSImageView는 이미지 원본 크기를 고유(최소) 크기로
/// 요구해, 세로로 긴 이미지가 칸 높이를 넘겨 상위 VStack을 밀어내고 서브탭 바를 화면 밖으로 잘라버렸다.
/// 최소 크기 요구를 없애 SwiftUI가 준 프레임에만 맞춰 그리게 한다(축소는 imageScaling이 담당).
final class FittingImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// 영상 파일 뷰어 탭 — AVKit 재생(재생/일시정지·탐색 컨트롤 포함).
struct VideoFileView: View {
    let target: FileViewTarget
    var chrome: Bool = true
    var onClose: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            if chrome {
                ViewerHeader(icon: target.tabIcon, title: target.path, onClose: onClose)
                Rectangle().fill(Color.pBorder).frame(height: 1)
            }
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        // 탭 전환·다른 영상으로 바뀌면 플레이어를 재생성, 사라질 때 정지.
        .task(id: target.id) {
            player = AVPlayer(url: URL(fileURLWithPath: target.path))
        }
        .onDisappear { player?.pause() }
    }
}
