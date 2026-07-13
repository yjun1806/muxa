import SwiftUI

/// 뷰어 탭 공통 헤더 — 아이콘 + 경로 + 닫기(Esc). (DiffView.header 패턴을 뷰어들이 공유)
struct ViewerHeader: View {
    let icon: String
    let title: String
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.muxa(.body)).foregroundStyle(Color.pMuted)
            Text(title)
                .font(.muxaMono(.body, weight: .medium))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            Button("닫기", action: onClose)
                .keyboardShortcut(.cancelAction) // Esc
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.pPanel)
    }
}
