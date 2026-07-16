import SwiftUI

/// 새 리뷰 코멘트를 달 줄의 앵커 정보 + 입력 초안. .sheet(item:)용 Identifiable.
struct CommentDraft: Identifiable {
    let id = UUID()
    let file: String
    let side: DiffSide
    let line: Int
    let lineText: String
}

/// 줄 코멘트 입력 시트 — 앵커 줄 미리보기 + 본문 입력 + 저장/취소. 저장 시 onSubmit(본문).
struct ReviewCommentSheet: View {
    let draft: CommentDraft
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var body_ = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").foregroundStyle(Color.pMuted)
                Text("리뷰 코멘트").font(.muxa(.title, weight: .semibold)).foregroundStyle(Color.pFg)
                Spacer()
                Text("\(basename(draft.file)):\(draft.line)")
                    .font(.muxaMono(.label)).foregroundStyle(Color.pMuted)
            }
            Text(draft.lineText.isEmpty ? " " : draft.lineText)
                .font(.muxaMono(.label))
                .foregroundStyle(Color.pMuted)
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))

            TextEditor(text: $body_)
                .font(.muxa(.body))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))

            HStack {
                Spacer()
                Button("취소", action: onCancel).keyboardShortcut(.cancelAction)
                Button("저장") { onSubmit(body_) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Color.pPanel)
    }
}
