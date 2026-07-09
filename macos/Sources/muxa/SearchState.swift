import Foundation

/// 한 터미널의 스크롤백 검색 상태 — 오버레이 표시 여부와 매치 카운터를 담는다.
/// ghostty가 검색 액션(SEARCH_TOTAL/SELECTED)으로 total·selected를 되돌려주면 여기에 반영된다.
///
/// needle→ghostty 전달은 전용 C API가 없어 `ghostty_surface_binding_action("search:<needle>")`
/// 문자열로만 가능하다(cmux 동일). 그 브리지는 TermView가 `applyNeedle`로 주입한다.
@MainActor
final class SearchState: ObservableObject {
    @Published var active = false
    @Published var needle = ""
    @Published var total: Int? = nil // 미확정(-1)이면 nil
    @Published var selected: Int? = nil // 0-based 매치 인덱스, 없으면 nil

    /// needle을 ghostty로 밀어넣는 브리지(TermView가 세팅).
    var applyNeedle: ((String) -> Void)?

    private var debounce: DispatchWorkItem?

    /// 검색어 변경 반영 — 빈 문자열/3자 이상은 즉시, 그 미만은 300ms 디바운스(cmux 방식).
    /// 짧은 needle은 매치가 폭발적이라 매 키마다 검색하면 렉이 생긴다.
    func commitNeedle() {
        debounce?.cancel()
        let n = needle
        let job: () -> Void = { [weak self] in
            self?.applyNeedle?(n)
        }
        if n.isEmpty || n.count >= 3 {
            job()
        } else {
            let work = DispatchWorkItem(block: job)
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    /// 오버레이를 닫을 때 상태 초기화(active=false는 호출부에서).
    func reset() {
        debounce?.cancel()
        needle = ""
        total = nil
        selected = nil
    }
}
