import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 워크스페이스 사이드바 **드래그 앤 드롭 재정렬**(YJ-1).
///
/// 창이 `isMovableByWindowBackground`(빈 영역 드래그로 창 이동, `MuxaWindowController`)라
/// 순수 SwiftUI `.onDrag`는 **창 이동에 드래그를 뺏긴다** — 리사이즈 핸들이 AppKit으로 간 것과
/// 같은 사정(`PanelResizeHandle`). 그래서 드래그 **소스**는 행 위의 작은 **그립 핸들**(AppKit,
/// `mouseDownCanMoveWindow=false`)이 담당해 창 이동을 막고 여기서 드래그 세션을 직접 연다.
/// **드롭**은 SwiftUI가 받는다(전용 UTType이라 AppKit 세션도 그대로 수신) — 삽입선·`moveWorkspace`
/// 재사용. 순서의 진실은 `AppState.workspaces` 배열 위치(정렬 필드 없음).
///
/// 그립은 확장 모드에만 있다(compact/slim은 폭이 좁아 그립 자리가 없어 재정렬 미지원 — 이름이
/// 보이는 확장 모드가 재정렬이 의미 있는 곳이다).

extension UTType {
    /// 워크스페이스 재정렬 전용 드래그 타입. **이 타입으로만 드롭을 받아** 외부 텍스트/파일 드래그가
    /// 순서를 건드리는 일을 막는다. 앱 내부 전용이라 Info.plist 선언 없이 쓴다(프로세스 내 드래그는
    /// 식별자 문자열로 매칭).
    static let muxaWorkspaceReorder = UTType(exportedAs: "com.muxa.workspace-reorder")
}

/// 지금 삽입선을 그릴 자리 — 어느 행의 위/아래에 그릴지.
struct WorkspaceDropMark: Equatable {
    let targetId: String
    let before: Bool
}

extension View {
    /// 드래그 소스(그립) + 드롭 대상. **고정 높이 행**에 붙인다(위/아래 절반 판정에 `RowHeight.row`를 씀).
    /// `isHovered`일 때만 그립을 보이고 히트테스트한다 — 안 그러면 좌측 강조 영역이 늘 마우스를 먹는다.
    func workspaceReorderRow(id: String, state: AppState, isHovered: Bool,
                             draggingId: Binding<String?>,
                             mark: Binding<WorkspaceDropMark?>) -> some View {
        modifier(WorkspaceReorderRow(id: id, state: state, isHovered: isHovered,
                                     draggingId: draggingId, mark: mark))
    }

    /// 삽입선. **그룹(행+자식 레인)**에 붙인다 — 펼침 시 "뒤로" 선이 자식 레인 아래로 가도록.
    func workspaceDropLine(id: String, mark: WorkspaceDropMark?) -> some View {
        overlay(alignment: .top) {
            WorkspaceDropLine(shown: mark == WorkspaceDropMark(targetId: id, before: true))
        }
        .overlay(alignment: .bottom) {
            WorkspaceDropLine(shown: mark == WorkspaceDropMark(targetId: id, before: false))
        }
    }
}

/// 삽입선 한 줄 — 대상·방향이 맞을 때만 그린다.
private struct WorkspaceDropLine: View {
    let shown: Bool
    var body: some View {
        if shown {
            Capsule().fill(Color.pBrand).frame(height: 2).padding(.horizontal, Space.sm)
        }
    }
}

private struct WorkspaceReorderRow: ViewModifier {
    let id: String
    let state: AppState
    let isHovered: Bool
    @Binding var draggingId: String?
    @Binding var mark: WorkspaceDropMark?

    func body(content: Content) -> some View {
        content
            // 그립 = 드래그 소스(AppKit). 호버 시에만 좌측 아바타 자리를 덮어 나타난다.
            .overlay(alignment: .leading) {
                ZStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.muxa(.micro, weight: .semibold))
                        .foregroundStyle(Color.pMuted)
                    WorkspaceDragGrip(id: id,
                                      onBegan: { draggingId = $0 },
                                      onEnded: { draggingId = nil })
                }
                .frame(width: IconSize.control, height: RowHeight.row)
                .background(Color.pBtnHover) // 호버 배경과 같은 색 — 아바타를 깔끔히 덮는다
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .padding(.leading, Space.sm) // 행 내부 좌측 패딩만큼 밀어 아바타 위에 정렬
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .onDrop(of: [.muxaWorkspaceReorder],
                    delegate: WorkspaceReorderDrop(targetId: id, rowHeight: RowHeight.row,
                                                   state: state,
                                                   draggingId: $draggingId, mark: $mark))
    }
}

/// 한 워크스페이스 행에 대한 드롭 대상. 포인터의 세로 위치로 위/아래 절반을 판정해 삽입선을
/// 갱신하고, 드롭되면 `moveWorkspace`를 호출한다.
private struct WorkspaceReorderDrop: DropDelegate {
    let targetId: String
    let rowHeight: CGFloat
    let state: AppState
    @Binding var draggingId: String?
    @Binding var mark: WorkspaceDropMark?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = draggingId else { return false }
        return dragging != targetId // 자기 자신 위로는 드롭 무의미
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if mark?.targetId == targetId { mark = nil } // 이 행을 벗어날 때 이 행의 삽입선만 지운다
    }

    func performDrop(info: DropInfo) -> Bool {
        let before = info.location.y < rowHeight / 2
        let dragged = draggingId
        mark = nil
        guard let dragged, dragged != targetId else { return false }
        // 재정렬은 @MainActor. SwiftUI가 이 콜백을 메인에서 부르지만, off-main이어도 크래시하지 않도록
        // 메인 홉으로 넘긴다. 반영은 다음 런루프 틱 — 체감 불가. (draggingId는 그립의 drag-end가 정리)
        Task { @MainActor in
            state.moveWorkspace(dragged, adjacentTo: targetId, placeBefore: before)
        }
        return true
    }

    /// 포인터가 행의 위 절반이면 '앞', 아래 절반이면 '뒤'에 삽입선.
    private func update(_ info: DropInfo) {
        guard let dragging = draggingId, dragging != targetId else { return }
        mark = WorkspaceDropMark(targetId: targetId, before: info.location.y < rowHeight / 2)
    }
}

// MARK: - 그립(AppKit 드래그 소스)

/// 투명 AppKit 뷰. 위의 SwiftUI 그립 글리프 위에 얹혀 마우스를 받아, 창 이동을 막고
/// (`mouseDownCanMoveWindow=false`) 재정렬 드래그 세션을 시작한다.
private struct WorkspaceDragGrip: NSViewRepresentable {
    let id: String
    let onBegan: (String) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> WorkspaceDragGripNSView {
        let v = WorkspaceDragGripNSView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: WorkspaceDragGripNSView, context: Context) { apply(to: v) }

    private func apply(to v: WorkspaceDragGripNSView) {
        v.workspaceId = id
        v.onBegan = onBegan
        v.onEnded = onEnded
    }
}

final class WorkspaceDragGripNSView: NSView, NSDraggingSource {
    var workspaceId = ""
    var onBegan: ((String) -> Void)?
    var onEnded: (() -> Void)?

    /// 드래그 시작 판정용 mouseDown 지점(창 좌표). nil이면 트래킹 중 아님.
    private var downPoint: NSPoint?

    /// 이 뷰 위 mouseDown은 창을 움직이지 않는다 — 재정렬 드래그만(창 이동과의 충돌 차단).
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard dx * dx + dy * dy > 9 else { return } // 3pt 임계값 — 미세 흔들림은 클릭으로 둔다
        downPoint = nil
        beginReorderDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) { downPoint = nil }

    private func beginReorderDrag(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setData(Data(workspaceId.utf8),
                     forType: NSPasteboard.PasteboardType(UTType.muxaWorkspaceReorder.identifier))
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: dragImage())
        onBegan?(workspaceId)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    /// 드래그 프리뷰 — 은은한 브랜드색 알약(정확한 행 스냅샷 대신 가벼운 힌트, 실제 피드백은 삽입선).
    private func dragImage() -> NSImage {
        let size = NSSize(width: 120, height: RowHeight.row)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(Color.pBrand).withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: Radius.sm, yRadius: Radius.sm).fill()
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

    /// 드롭 성공이든 취소든 여기서 소스 상태를 정리한다 — stale `draggingId`가 안 남는다.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onEnded?()
    }
}
