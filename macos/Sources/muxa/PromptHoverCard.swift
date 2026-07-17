import AppKit
import SwiftUI

/// hover 카드 — **잘린 프롬프트의 전문과 첨부 이미지**를 보여준다.
/// 사이드바 에이전트 행(제목이 프롬프트로 승격돼 잘린다)과 백그라운드 팝오버(❯ 줄)가 공용으로 쓴다.
///
/// 카드 창(`TipWindow`)은 표시 시점 크기로 고정되므로, 이미지는 자리(placeholder)를 먼저 잡고
/// 로드가 끝나면 채운다 — 카드가 뜬 뒤 커지지 않는다. 이미지는 transcript(JSONL)의 마지막
/// user 메시지에서 읽는다(`TranscriptTail.lastUserImages`).
struct PromptHoverCard: View {
    /// 프롬프트 전문(저장 시 이미 상한 클램프됨 — `AgentPrompt.textMax`).
    let text: String
    let imageCount: Int
    /// 이미지를 읽어 올 transcript 경로 — 없으면 자리(placeholder)만 보인다.
    let transcriptPath: String?

    @State private var images: [NSImage] = []

    /// 카드 최대 폭 — 사이드바 옆에 뜨는 카드라 본문 폭을 과하게 키우지 않는다.
    private static let maxWidth: CGFloat = 340
    /// 이미지 미리보기 크기(고정) — 로드 전후 카드 크기가 흔들리지 않는 자리의 근거.
    private static let thumbSize = CGSize(width: 104, height: 78)
    /// 카드에 싣는 이미지 상한 — "그 스크린샷 건"을 짚는 데는 몇 장이면 충분하다.
    static let imageLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if !text.isEmpty {
                Text(text)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pFg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if imageCount > 0 { thumbnails }
        }
        .padding(Space.md)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .background(Color.pPanel)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
            .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        .shadow(color: .black.opacity(Elevation.keyOpacity),
                radius: Elevation.keyRadius, y: Elevation.keyOffsetY)
        .padding(Elevation.margin) // 그림자가 창 경계에서 잘리지 않을 자리(TipChip과 같은 사정)
        .task { await load() }
    }

    /// 이미지 줄 — 로드 전엔 무채 자리, 로드되면 채운다. 상한 넘으면 "+N"으로 접는다.
    private var thumbnails: some View {
        HStack(spacing: Space.sm) {
            ForEach(0..<min(imageCount, Self.imageLimit), id: \.self) { index in
                thumb(index)
            }
            if imageCount > Self.imageLimit {
                Text("+\(imageCount - Self.imageLimit)")
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
            }
        }
    }

    private func thumb(_ index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.pLane)
            if index < images.count {
                Image(nsImage: images[index])
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.muxa(.body))
                    .foregroundStyle(Color.pMuted)
            }
        }
        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
            .stroke(Color.pBorder, lineWidth: RowHeight.hairline))
    }

    private func load() async {
        guard imageCount > 0, let transcriptPath else { return }
        let datas = await TranscriptTail.lastUserImages(atPath: transcriptPath, limit: Self.imageLimit)
        images = datas.compactMap { NSImage(data: $0) }
    }
}

/// 첨부 이미지 칩 — "hover하면 보인다"의 어포던스. 개수만 조용히(무채) 말한다.
/// 사이드바 에이전트 행·백그라운드 팝오버가 공용으로 쓴다(카드와 세트).
struct PromptImageChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "photo").font(.muxa(.micro))
            Text("\(count)").font(.muxaMono(.caption))
        }
        .foregroundStyle(Color.pMuted)
        .accessibilityLabel("첨부 이미지 \(count)장")
    }
}
