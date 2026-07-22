import Foundation
import Observation

/// 인앱 브라우저 서브탭 하나의 상태 — 현재 URL·제목·네비게이션 가능 여부를 관측 가능하게 들고 있다.
/// WKWebView(부작용)는 BrowserWebView가 소유하고, 여기엔 명령 훅(클로저)만 대입한다
/// (TerminalStore가 term.onFocus를 대입하는 패턴과 같다). 상태는 위(여기), 표현은 아래(BrowserWebView).
@MainActor
@Observable
final class BrowserTab: Identifiable {
    /// 서브탭 dedup·복원 키. 최초 URL로 고정 — 페이지 내 네비게이션으로 currentURL이 바뀌어도 유지된다.
    let id: String
    /// 복원·최초 표시용. lazy 로드는 이 URL로 시작한다.
    let initialURL: URL

    var currentURL: URL
    var pageTitle: String
    var addressText: String    // 주소창 편집 텍스트(currentURL과 별개로 사용자가 타이핑)
    var canGoBack = false
    var canGoForward = false
    var isLoading = false

    /// lazy 로드 1회 가드 — 서브탭이 처음 보일 때만 initialURL을 실제로 로드한다.
    @ObservationIgnored var hasStartedLoading = false

    /// 주소창 편집 중 여부 — 네비게이션이 사용자의 입력을 덮어쓰지 않게 하는 가드.
    @ObservationIgnored var isEditingAddress = false

    // 명령 훅 — BrowserWebView가 makeNSView에서 대입한다. 버튼·주소창이 호출한다.
    @ObservationIgnored var goBackAction: () -> Void = {}
    @ObservationIgnored var goForwardAction: () -> Void = {}
    @ObservationIgnored var reloadAction: () -> Void = {}
    @ObservationIgnored var stopAction: () -> Void = {}
    @ObservationIgnored var loadAction: (URL) -> Void = { _ in }

    /// 페이지 로드 완료 시 호출 — 스토어가 대입해 currentURL 변경을 스냅샷에 남긴다(복원 정확도).
    @ObservationIgnored var onNavigated: () -> Void = {}

    init(url: URL) {
        self.id = "web:\(url.absoluteString)"
        self.initialURL = url
        self.currentURL = url
        self.addressText = url.absoluteString
        self.pageTitle = url.host ?? url.absoluteString
    }

    /// 주소창 제출 — 유효 URL이면 로드한다. 잘못된 입력은 무시.
    func submitAddress() {
        guard let url = normalizeBrowserAddress(addressText) else { return }
        loadAction(url)
    }
}
