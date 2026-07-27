import AppKit
import SwiftUI

/// 워크스페이스 사이드바 **그립 드래그 재정렬**(YJ-1) — dnd-kit식 연출.
///
/// 창이 `isMovableByWindowBackground`(빈 영역 드래그로 창 이동, `MuxaWindowController`)라
/// 순수 SwiftUI `.onDrag`는 **창 이동에 드래그를 뺏긴다** — 그래서 행 좌측의 작은 **그립**이
/// AppKit 뷰(`mouseDownCanMoveWindow=false`)로 마우스를 직접 받는다. 시스템 드래그 세션도 쓰지
/// 않는다(열어 보면 SwiftUI 드롭이 그 세션을 전혀 인지하지 못해 `validateDrop`이 안 불린다).
///
/// **역할 분담**: AppKit 그립은 *커서 이동량(dy)* 만 올려보내고, **기하 판정은 전부 SwiftUI가**
/// 한다 — 행 프레임을 `PreferenceKey`로 모아 두었다가 커서 위치로 삽입 자리를 고른다
/// (`SidebarTree.dropTarget`). 좌표계 변환(AppKit y-up ↔ SwiftUI y-down)이 그립에서 사라진다.
///
/// 그립은 확장 모드에만 있다(compact/slim은 폭이 좁아 그립 자리가 없다).
/// 순서의 진실은 `AppState.workspaces` 배열 위치(정렬 필드 없음).

/// 사이드바 트리의 좌표계 — 행 프레임과 떠 있는 복사본이 같은 원점을 쓰게 묶는다.
enum SidebarTreeSpace {
    static let name = "muxa.sidebar.tree"
}

/// 삽입 자리 — 어느 행의 앞/뒤인가.
struct WorkspaceDropSlot: Equatable {
    let targetId: String
    let before: Bool
}

/// 진행 중인 그립 드래그. 없으면(nil) 평상시 렌더다.
struct WorkspaceDrag: Equatable {
    let id: String
    /// **드래그 시작 시점**의 행 프레임 스냅샷. 프리뷰가 재정렬되면 살아 있는 프레임이 같이
    /// 움직여 되먹임(떨림)이 생기므로, 판정 기준은 시작 때 얼려 둔 이 값만 쓴다.
    let startFrames: [String: CGRect]
    /// 시작점 기준 커서 세로 이동량(아래로 +).
    var deltaY: CGFloat = 0
    /// 지금 가리키는 삽입 자리. nil이면 제자리(이동 없음).
    var target: WorkspaceDropSlot?
}

// MARK: - 행 프레임 수집

private struct WorkspaceRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 이 행의 프레임을 트리 좌표계로 올려보낸다 — 대상 판정과 복사본 위치의 기준.
    func workspaceRowFrame(id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: WorkspaceRowFrames.self,
                                       value: [id: geo.frame(in: .named(SidebarTreeSpace.name))])
            }
        )
    }

    /// 모아진 행 프레임을 받는다(트리 컨테이너에 한 번만 붙인다).
    func onWorkspaceRowFrames(_ action: @escaping ([String: CGRect]) -> Void) -> some View {
        onPreferenceChange(WorkspaceRowFrames.self, perform: action)
    }
}

// MARK: - 그립

extension View {
    /// 행 좌측에 드래그 그립을 얹는다. **고정 높이 행**에 붙인다.
    func workspaceReorderGrip(id: String, state: AppState,
                              hoveredId: Binding<String?>,
                              drag: Binding<WorkspaceDrag?>,
                              rowFrames: [String: CGRect]) -> some View {
        modifier(WorkspaceReorderGrip(id: id, state: state, hoveredId: hoveredId,
                                      drag: drag, rowFrames: rowFrames))
    }
}

private struct WorkspaceReorderGrip: ViewModifier {
    let id: String
    let state: AppState
    @Binding var hoveredId: String?
    @Binding var drag: WorkspaceDrag?
    let rowFrames: [String: CGRect]

    private var isHovered: Bool { hoveredId == id }

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            ZStack {
                // **아바타 슬롯을 그대로 대치한다** — 같은 상자(`inlineMark`)를 같은 자리에 덮어,
                // 호버하면 아바타가 그립으로 *바뀐* 것처럼 보이게 한다(상자가 크면 이름 쪽으로
                // 삐져나와 어색하다). 덮개 색이 행의 호버 배경과 같아 이음매가 안 보인다.
                //
                // 글리프만 hover로 페이드한다 — **히트영역(AppKit 뷰)은 늘 살아 있다.**
                // 히트테스트를 hover로 껐다 켜면, 그립이 마우스를 가져가 hover가 풀리고 → 그립이
                // 꺼지고 → 다시 hover가 붙는 왕복이 생겨 심하게 깜박였다.
                Image(systemName: "line.3.horizontal")
                    .font(.muxa(.micro, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: IconSize.inlineMark, height: IconSize.inlineMark)
                    .background(Color.pBtnHover)
                    .opacity(isHovered ? 1 : 0)
                WorkspaceGrip(onHover: { hovering in
                                  // `.mouseMoved`로 매 이벤트마다 들어오므로 값이 실제로 바뀔 때만 쓴다.
                                  if hovering { if hoveredId != id { hoveredId = id } }
                                  else if hoveredId == id { hoveredId = nil }
                              },
                              // 끌지 않은 클릭은 행을 누른 것과 같게 — 좌측 13pt가 죽지 않는다.
                              onClick: { state.toggleWorkspaceExpansion(id) },
                              onBegan: began, onChanged: changed,
                              onEnded: ended, onCancel: { drag = nil })
            }
            // 폭은 아바타와 같게, **높이는 행 전체**로 — 13pt 정사각만 주면 잡기가 너무 까다롭다.
            // 늘어난 부분은 투명해서 보이지 않는다(대치되는 모습은 위 13×13 상자가 전부다).
            .frame(width: IconSize.inlineMark, height: RowHeight.row)
            .padding(.leading, Space.sm) // 행 내부 좌측 패딩만큼 밀어 아바타 위에 정렬
        }
    }

    private func began() {
        drag = WorkspaceDrag(id: id, startFrames: rowFrames)
    }

    private func changed(_ deltaY: CGFloat) {
        guard var next = drag, let start = next.startFrames[id] else { return }
        next.deltaY = deltaY
        let mids = next.startFrames.map { (id: $0.key, midY: $0.value.midY) }
        next.target = SidebarTree.dropTarget(y: start.midY + deltaY, rowMids: mids, dragged: id)
            .map { WorkspaceDropSlot(targetId: $0.targetId, before: $0.placeBefore) }
        drag = next
    }

    private func ended() {
        if let target = drag?.target {
            state.moveWorkspace(id, adjacentTo: target.targetId, placeBefore: target.before)
        }
        drag = nil
    }
}

// MARK: - 떠 있는 복사본

/// 커서를 따라다니는 행 복사본(dnd-kit의 DragOverlay). 트리 좌표계 원점 기준으로 놓이므로
/// **트리 컨테이너의 `.overlay(alignment: .topLeading)`** 에 넣어야 자리가 맞는다.
struct WorkspaceDragPreview: View {
    let state: AppState
    let drag: WorkspaceDrag
    let workspace: Workspace
    let index: Int

    var body: some View {
        if let start = drag.startFrames[drag.id] {
            SidebarWorkspaceRow(state: state, workspace: workspace, index: index,
                                hoveredId: .constant(workspace.id), menuOpenId: .constant(nil))
                .frame(width: start.width)
                .background(Color.pPanel) // 아래 행이 비쳐 보이지 않게 — 들려 있다는 신호
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .shadow(color: .black.opacity(Elevation.keyOpacity),
                        radius: Elevation.keyRadius, y: Elevation.keyOffsetY)
                .scaleEffect(1.03) // 손에 들려 살짝 가까워진 느낌
                .offset(y: start.minY + drag.deltaY)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 그립(AppKit 마우스 트래킹)

private struct WorkspaceGrip: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onBegan: () -> Void
    let onChanged: (_ deltaY: CGFloat) -> Void
    let onEnded: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> WorkspaceGripView {
        let v = WorkspaceGripView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: WorkspaceGripView, context: Context) { apply(to: v) }

    private func apply(to v: WorkspaceGripView) {
        v.onHover = onHover
        v.onClick = onClick
        v.onBegan = onBegan
        v.onChanged = onChanged
        v.onEnded = onEnded
        v.onCancel = onCancel
    }
}

final class WorkspaceGripView: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onBegan: (() -> Void)?
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
    var onCancel: (() -> Void)?

    /// 드래그 시작 판정용 mouseDown 지점(창 좌표). nil이면 버튼을 누르고 있지 않다.
    private var downPoint: NSPoint?
    /// 임계값을 넘겨 실제 재정렬 드래그로 들어갔는가.
    private var dragging = false
    /// Esc로 취소된 뒤 도착하는 mouseUp이 이동이나 클릭으로 오해되지 않게 하는 표식.
    private var cancelled = false
    private var tracking: NSTrackingArea?
    /// 드래그 중에만 사는 Esc 감시자 — 평상시엔 이벤트 흐름에 아무것도 얹지 않는다.
    private var escMonitor: Any?

    deinit { removeEscMonitor() }

    /// 이 뷰 위 mouseDown은 창을 움직이지 않는다 — 재정렬 드래그만(창 이동과의 충돌 차단).
    override var mouseDownCanMoveWindow: Bool { false }

    /// 우클릭은 통과시킨다 — 아래 `RightClickCatcher`(`sidebarRow`)가 행 메뉴를 연다.
    /// 안 그러면 좌측 24pt에서만 우클릭 메뉴가 죽는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp: return nil
        default: return super.hitTest(point)
        }
    }

    /// hover는 **이 뷰가 소유한다**(행의 SwiftUI `.onHover`가 아니라). `.mouseMoved`까지 켜는 이유:
    /// 행 쪽 `.onHover`가 이 뷰 진입을 "행에서 나감"으로 읽고 hover를 꺼도 다음 움직임에 되살린다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.activeInActiveApp, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseMoved(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) {
        guard !dragging else { return } // 드래그 중엔 커서가 그립을 벗어나도 그립을 붙들어 둔다
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
        cancelled = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !cancelled else { return }
        if !dragging {
            let dx = event.locationInWindow.x - start.x
            let dy = event.locationInWindow.y - start.y
            guard dx * dx + dy * dy > 9 else { return } // 3pt 임계값 — 미세 흔들림은 클릭으로 둔다
            dragging = true
            NSCursor.closedHand.set()
            installEscMonitor()
            onBegan?()
        }
        // AppKit은 y가 위로 커진다 — 화면에서 아래로 끈 만큼이 +가 되도록 뒤집어 넘긴다.
        onChanged?(start.y - event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        let wasCancelled = cancelled
        reset()
        guard !wasCancelled else { return } // Esc로 이미 끝난 드래그 — 이동도 클릭도 아니다
        if wasDragging { onEnded?() } else { onClick?() }
    }

    /// Esc = 취소. 원래 순서로 돌려놓고 드래그를 끝낸다(dnd-kit과 같은 탈출구).
    /// 손은 아직 버튼을 누르고 있을 수 있으므로 `cancelled`로 표시만 하고, 뒤따라 올 mouseUp이
    /// 이동/클릭으로 오해되지 않게 한다.
    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Esc
            guard let self, self.dragging else { return event }
            self.cancelled = true
            self.dragging = false
            self.removeEscMonitor()
            NSCursor.openHand.set()
            self.onCancel?()
            return nil // 취소를 여기서 소비한다 — 다른 Esc 동작까지 겸하지 않게
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    private func reset() {
        downPoint = nil
        dragging = false
        cancelled = false
        removeEscMonitor()
        NSCursor.openHand.set()
    }
}
