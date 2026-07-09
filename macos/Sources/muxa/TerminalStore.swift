import AppKit
import Bonsplit
import GhosttyKit
import Observation

/// 워크스페이스 하나의 터미널 집합 + Bonsplit 분할·탭 컨트롤러. (cmux DockSplitStore 대응)
///
/// Bonsplit이 분할 트리·탭 레이아웃을 SwiftUI로 관리하고, 우리는 tabId마다 TermView 하나를
/// 만들어 매핑한다(패인 내용 = 그 tabId의 터미널). 수동 AppKit 레이아웃이 없어져
/// 제약 엔진 폭주(분할 크래시)가 원천 소멸한다.
@MainActor
@Observable
final class TerminalStore: NSObject, BonsplitDelegate {
    let controller: BonsplitController

    @ObservationIgnored private let app: ghostty_app_t
    @ObservationIgnored private let cwd: String?
    @ObservationIgnored private var terms: [TabID: TermView] = [:]

    init(app: ghostty_app_t, cwd: String?) {
        self.app = app
        self.cwd = cwd
        self.controller = BonsplitController()
        super.init()
        controller.delegate = self
    }

    // MARK: BonsplitDelegate — 분할·새탭·닫기에 터미널 생명주기를 잇는다

    /// 분할 즉시 새 패인에 터미널을 만든다 — 빈 패인을 거치지 않는다(muxa 원래 동작).
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        newTerminal(inPane: newPane)
    }

    /// 탭바 `+` 버튼 → 새 터미널.
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
        newTerminal(inPane: pane)
    }

    /// 탭이 닫히면 그 터미널(PTY·서피스)을 해제한다.
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {
        terms[tabId] = nil // TermView deinit이 서피스 free
    }

    /// tabId에 대응하는 터미널 뷰(없으면 생성). 패인 내용 렌더에서 호출한다.
    func term(for tabId: TabID) -> TermView {
        if let t = terms[tabId] { return t }
        let t = TermView(app: app, cwd: cwd)
        terms[tabId] = t
        return t
    }

    /// 새 터미널 탭 생성(분할 후 빈 패인 채우기·⌘T 등).
    @discardableResult
    func newTerminal(inPane pane: PaneID? = nil) -> TabID? {
        controller.createTab(title: "터미널", icon: "terminal", inPane: pane)
    }

    /// 초기 터미널 1개 보장(워크스페이스 최초 표시 시).
    func ensureInitialTerminal() {
        if controller.allTabIds.isEmpty {
            newTerminal()
        }
    }

    /// [PoC] 분할 크래시 검증용 — 가로/세로로 두 번 분할하고 각 빈 패인에 터미널을 넣는다.
    func debugAutoSplit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if let p = self.controller.splitPane(orientation: .horizontal) {
                self.newTerminal(inPane: p)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                if let p = self.controller.splitPane(orientation: .vertical) {
                    self.newTerminal(inPane: p)
                }
            }
        }
    }
}
