import SwiftUI

/// git 커밋 입력 박스 — 메시지 + 커밋 버튼(스테이지된 변경 있을 때만 활성).
/// 상태(메시지·에러)는 상위(GitPanel)가 소유하고 controlled로 받는다.
struct GitCommitBox: View {
    @Binding var message: String
    let stagedCount: Int
    let error: String?
    var onCommit: () -> Void

    private var canCommit: Bool {
        stagedCount > 0 && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("커밋 메시지", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.muxa(.body))
                .lineLimit(1...4)
                .padding(6)
                .background(Color.pBg)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.pBorder, lineWidth: 1))
                .onSubmit { if canCommit { onCommit() } }
            if let error {
                Text(error)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pDanger)
                    .lineLimit(2)
            }
            Button(action: onCommit) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.muxa(.caption, weight: .bold))
                    Text(stagedCount > 0 ? "커밋 (\(stagedCount))" : "커밋")
                        .font(.muxa(.body, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(canCommit ? Color.accentColor : Color.pBorder)
                .foregroundStyle(canCommit ? Color.white : Color.pMuted)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .disabled(!canCommit)
        }
        .padding(8)
    }
}
