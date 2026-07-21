import SwiftUI

/// 스크래치(~) 독립 창의 루트 — 워크스페이스/projectWindows와 **무관한** 앱 레벨 터미널 공간.
///
/// `ProjectWindowView`를 쓰지 않는다: 그건 `located()`/`store(for:in:)`/`projectWindows`를 경유하는데,
/// 스크래치는 어디에도 속하지 않아 그 경로를 못 탄다. 사이드바·익스플로러·Git·브레드크럼 없이
/// 최소 상단바(신호등 여백 + 라벨) 아래로 스크래치 store의 터미널만 직접 렌더한다.
struct ScratchWindowView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) { // 최소 상단바 — 신호등 여백 + 라벨
                Color.clear.frame(width: TrafficLights.reservedLeadingWidth)
                Text(Scratch.label).font(.muxa(.body)).foregroundStyle(Color.pMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg)
            .frame(height: RowHeight.topBar)
            // owner가 Scratch.windowId로 박힌 store라 이 창의 뷰 트리에 surface가 붙는다(TermAttach).
            // **비스폰 조회**를 쓴다: openScratchWindow가 창을 열기 전에 store를 먼저 만들므로 정상 렌더 땐
            // 항상 존재한다. 뷰에서 scratchStore()(스폰형)를 부르면 창을 닫는 중 body가 재평가될 때
            // 렌더되지 않는 고아 store+PTY를 되살릴 수 있다 — 스폰은 경계(openScratchWindow)에만 둔다.
            if let store = state.existingStore(Scratch.projectId) {
                BonsplitWorkspaceView(store: store, windowId: Scratch.windowId.rawValue)
                    .contentCard(radius: Radius.lg, border: Color.pBorder)
                    .padding(.horizontal, Space.sm)
                    .padding(.bottom, Space.xs)
            } else {
                Color.clear // 닫는 중 일시적 — store가 없으면 아무것도 그리지 않는다(재생성하지 않는다)
            }
        }
        .background(Color.pPanel)
    }
}
