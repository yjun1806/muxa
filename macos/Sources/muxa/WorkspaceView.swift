import AppKit
import Carbon.HIToolbox
import GhosttyKit

/// 워크스페이스 하나의 분할 터미널 트리를 렌더한다. (src/WorkspaceView.tsx의 AppKit 이식)
///
/// computeLayout으로 각 패인의 사각형(%)을 계산해 절대 프레임으로 배치한다.
/// 각 패인은 PaneContainerView(헤더 + TermView)로 감싸며, id별로 재사용하므로
/// 트리가 재구성돼도 서피스·PTY가 유지된다.
///
/// M1 초기: tree/focusedId를 이 뷰가 소유한다. 세션 복구(상위 소유)를 붙일 때 controlled로
/// 전환한다 — 기존 WorkspaceView.tsx처럼 상위가 tree를 갖고 onChange로 위임하는 형태.
final class WorkspaceView: NSView {
    private let app: ghostty_app_t
    private let cwd: String?
    private var tree: TreeNode
    private var focusedId: String
    private let onTreeChange: (TreeNode, String) -> Void
    private var containers: [String: PaneContainerView] = [:]
    private var dividerViews: [String: DividerView] = [:] // key: SplitDivider.key

    init(app: ghostty_app_t, tab: TermTab, cwd: String?, onTreeChange: @escaping (TreeNode, String) -> Void) {
        self.app = app
        self.cwd = cwd
        self.tree = tab.tree
        self.focusedId = tab.focusedId
        self.onTreeChange = onTreeChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true } // 좌상단 원점 — tree의 % 좌표와 일치

    // MARK: 레이아웃

    override func layout() {
        super.layout()
        relayout()
    }

    private func relayout() {
        let ids = collectPaneIds(tree)

        // 트리에서 사라진 패인의 컨테이너 제거(PTY 종료)
        for (id, view) in containers where !ids.contains(id) {
            view.removeFromSuperview()
            containers[id] = nil
        }

        let layout = computeLayout(tree)
        for id in ids {
            let view = container(for: id)
            if let r = layout.panes[id] {
                view.frame = pixelRect(r)
            }
            view.focused = (id == focusedId)
        }

        // 구분선 재사용 — 매 레이아웃마다 재생성하면 레이아웃 도중 서브뷰 추가/제거가
        // 다시 레이아웃을 트리거해 무한 루프(창 크래시)가 된다. key로 매칭해 프레임만 갱신한다.
        let keys = Set(layout.dividers.map(\.key))
        for (key, view) in dividerViews where !keys.contains(key) {
            view.removeFromSuperview()
            dividerViews[key] = nil
        }
        for d in layout.dividers {
            let view = dividerView(for: d)
            view.divider = d
            view.frame = dividerPixelRect(d)
        }
    }

    private func dividerView(for d: SplitDivider) -> DividerView {
        if let existing = dividerViews[d.key] { return existing }
        let view = DividerView(divider: d) { [weak self] div, delta in self?.resize(div, by: delta) }
        dividerViews[d.key] = view
        addSubview(view) // 컨테이너 위(컨테이너는 .below로 추가됨)
        return view
    }

    private func container(for id: String) -> PaneContainerView {
        if let existing = containers[id] { return existing }
        let term = TermView(app: app, cwd: cwd)
        term.onFocus = { [weak self] in self?.setFocus(id) }
        let view = PaneContainerView(
            paneId: id,
            term: term,
            onSplit: { [weak self] dir in self?.split(paneId: id, dir: dir) },
            onClose: { [weak self] in self?.closePane(paneId: id) }
        )
        containers[id] = view
        addSubview(view, positioned: .below, relativeTo: nil) // 구분선 아래
        return view
    }

    /// % 사각형 → 뷰 픽셀 프레임(isFlipped라 top 그대로).
    private func pixelRect(_ r: Rect) -> NSRect {
        NSRect(
            x: r.left / 100 * bounds.width,
            y: r.top / 100 * bounds.height,
            width: r.width / 100 * bounds.width,
            height: r.height / 100 * bounds.height
        )
    }

    private func dividerPixelRect(_ d: SplitDivider) -> NSRect {
        let thickness: CGFloat = 6
        if d.dir == .row {
            return NSRect(
                x: d.pos / 100 * bounds.width - thickness / 2,
                y: d.cross / 100 * bounds.height,
                width: thickness,
                height: d.crossSize / 100 * bounds.height
            )
        } else {
            return NSRect(
                x: d.cross / 100 * bounds.width,
                y: d.pos / 100 * bounds.height - thickness / 2,
                width: d.crossSize / 100 * bounds.width,
                height: thickness
            )
        }
    }

    // MARK: 트리 변환 (패인 헤더 버튼·키바인딩에서 호출)

    /// 특정 패인을 dir 방향으로 분할한다(헤더 버튼은 자기 패인을, 단축키는 focusedId를 대상으로).
    private func split(paneId: String, dir: Dir) {
        let result = splitPane(tree, targetId: paneId, dir: dir)
        tree = result.tree
        focusedId = result.newPaneId
        relayout()
        focusCurrent()
        onTreeChange(tree, focusedId)
    }

    private func closePane(paneId: String) {
        let next = muxa.closePane(tree, targetId: paneId)
        // 닫은 게 포커스 패인이면 첫 패인으로 포커스 이동
        if !collectPaneIds(next).contains(focusedId) {
            focusedId = firstPaneId(next)
        }
        tree = next
        relayout()
        focusCurrent()
        onTreeChange(tree, focusedId)
    }

    /// 클릭으로 포커스된 패인을 논리 focusedId로 반영(테두리·저장 갱신).
    private func setFocus(_ paneId: String) {
        guard focusedId != paneId else { return }
        focusedId = paneId
        for (id, view) in containers { view.focused = (id == paneId) }
        onTreeChange(tree, focusedId)
    }

    private func focusSibling(_ delta: Int) {
        focusedId = siblingPaneId(tree, focusedId: focusedId, delta: delta)
        relayout()
        focusCurrent()
        onTreeChange(tree, focusedId)
    }

    private func focusCurrent() {
        window?.makeFirstResponder(containers[focusedId]?.term)
    }

    /// 활성 워크스페이스로 전환됐을 때 상위(WorkspaceHostView)가 호출 — 포커스 패인에 first responder를 준다.
    func focusActivePane() {
        focusCurrent()
    }

    private func resize(_ d: SplitDivider, by pointerDelta: CGFloat) {
        let axisPx = d.axisPct / 100 * (d.dir == .row ? bounds.width : bounds.height)
        guard axisPx > 0 else { return }
        let total = d.sizes.reduce(0, +)
        let minSize = total * 0.05 // 최소 5%
        let deltaWeight = Double(pointerDelta) / Double(axisPx) * total
        var a = d.sizes[d.index] + deltaWeight
        var b = d.sizes[d.index + 1] - deltaWeight
        if a < minSize { b -= minSize - a; a = minSize }
        if b < minSize { a -= minSize - b; b = minSize }
        var newSizes = d.sizes
        newSizes[d.index] = a
        newSizes[d.index + 1] = b
        tree = setSplitSizes(tree, splitId: d.splitId, sizes: newSizes)
        relayout()
        onTreeChange(tree, focusedId)
    }

    // MARK: 키바인딩 — ⌘D 분할 / ⌘W 닫기 / ⌘] ⌘[ 포커스 이동
    // performKeyEquivalent는 first responder(TermView)의 keyDown보다 먼저 호출된다.
    // 물리 keyCode로 판별한다 — charactersIgnoringModifiers는 한글 등 자판 언어를 타서
    // ⌘D의 D가 "ㅇ"으로 오면 매칭에 실패한다.

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_D:
            split(paneId: focusedId, dir: event.modifierFlags.contains(.shift) ? .col : .row)
            return true
        case kVK_ANSI_W:
            closePane(paneId: focusedId)
            return true
        case kVK_ANSI_RightBracket:
            focusSibling(1)
            return true
        case kVK_ANSI_LeftBracket:
            focusSibling(-1)
            return true
        default:
            return false
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusCurrent()
    }
}
