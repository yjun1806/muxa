import SwiftUI

/// 우측 도구 패널(익스플로러·Git) 토글 — 켜져 있으면 배경이 눌린다.
///
/// 메인 창(ContentView)과 분리 창(ProjectWindowView)이 **같은 것**을 쓴다. 값의 출처만 다르고
/// (메인 = AppState 필드, 분리 창 = ProjectWindow) 생김새·크기·색은 하나여야 한다.
struct PanelToggle: View {
    let icon: String
    let on: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.muxa(.body))
                .foregroundStyle(on ? Color.pFg : Color.pMuted)
        }
        .buttonStyle(.plain)
        .clickCursor()
        .frame(width: IconSize.control, height: IconSize.control)
        .background(on ? Color.pBtnActive.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .help(help)
    }
}
