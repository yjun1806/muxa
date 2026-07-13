import AppKit
import SwiftUI

/// Bonsplit 패인 안에 터미널(TermView)을 넣는 SwiftUI 브리지.
/// Bonsplit이 패인 프레임을 SwiftUI 레이아웃으로 관리하므로, 여기선 TermView를 호스팅만 한다.
/// (수동 setFrame이 없어 제약 엔진 폭주가 발생하지 않는다.)
///
/// onFocus: 터미널 클릭 시 그 패인을 Bonsplit에 포커스시킨다 — 단축키(⌘D/⌘T/⌘W)가
/// 올바른 패인을 대상으로 삼도록. 터미널(NSView)이 클릭을 먼저 먹으므로 SwiftUI tap으론 부족하다.
struct TerminalRepresentable: NSViewRepresentable {
    let term: TermView
    let onFocus: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        // Bonsplit 패인 안에선 컨테이너 크기에 맞춰 autoresize한다 — 그러려면 translates=true여야 한다
        // (TermView.init은 구 수동 레이아웃용으로 false였음).
        term.translatesAutoresizingMaskIntoConstraints = true
        term.autoresizingMask = [.width, .height]
        term.frame = container.bounds
        container.addSubview(term)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        term.onFocus = onFocus // 매 렌더마다 현재 paneId로 갱신(탭 이동 대응)
        guard term.superview !== nsView else { return }
        // **화면에 붙어 있는 TermView를 화면 밖 컨테이너가 뺏어가지 못하게 한다.**
        //
        // TermView는 TerminalStore가 소유하는 단일 인스턴스인데, 복원 중 트리가 .pane → .split으로
        // 바뀌면 같은 TermView를 그리는 SwiftUI 뷰가 잠시 둘 공존한다. 그때 소유권 검사 없이
        // "내 자식이 아니면 가져온다"를 하면, **죽어가는 쪽이 나중에 돌 경우 TermView를 곧 폐기될
        // 계층으로 끌고 간다** — 화면의 칸은 빈 껍데기(흰 화면)로 남는다. 게다가 TermView가 계층에
        // 없으니 mouseDown조차 오지 않아 클릭으로도 복구되지 않는다(자기잠금).
        if term.window != nil, nsView.window == nil { return }
        term.removeFromSuperview()
        term.frame = nsView.bounds
        term.autoresizingMask = [.width, .height]
        nsView.addSubview(term)
    }
}
