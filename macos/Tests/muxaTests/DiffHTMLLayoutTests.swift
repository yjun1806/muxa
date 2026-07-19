import XCTest
@testable import muxa

/// 통합·나란히 diff HTML의 레이아웃 규약 — 좌우 스크롤 금지 + 변경 위치 레일.
///
/// 둘 다 "보이지 않으면 없는 것과 같다"는 성격이라 눈으로만 확인하면 조용히 되돌아간다.
/// (실제로 `width:max-content`가 오래 남아 긴 줄이 가로로 흘렀다.)
final class DiffHTMLLayoutTests: XCTestCase {

    private let sample = [
        "diff --git a/a.md b/a.md",
        "--- a/a.md",
        "+++ b/a.md",
        "@@ -1,3 +1,3 @@",
        " 그대로인 줄",
        "-지운 줄",
        "+더한 줄",
    ]

    private func unified() -> String { CodeHTML.diff(lines: sample, dark: false) }
    private func sideBySide() -> String { CodeHTML.diff(lines: sample, dark: false, sideBySide: true) }

    // MARK: 좌우 스크롤 금지

    /// 긴 줄은 **접어서 흘린다**. `max-content`면 표가 뷰포트보다 넓어져 가로 스크롤이 생긴다.
    func testNoHorizontalOverflowInUnified() {
        let html = unified()
        XCTAssertFalse(html.contains("width:max-content"), "가로 스크롤을 만드는 max-content가 남아 있다")
        XCTAssertTrue(html.contains("table.code{border-collapse:collapse;width:100%"))
    }

    func testNoHorizontalOverflowInSideBySide() {
        let html = sideBySide()
        XCTAssertFalse(html.contains("width:max-content"), "나란히 뷰에 max-content가 남아 있다")
        XCTAssertTrue(html.contains("table.sxs{border-collapse:collapse;width:100%"))
    }

    /// 내용 셀은 `pre-wrap` — 들여쓰기·연속 공백은 보존하되 줄은 접는다.
    /// `anywhere`가 없으면 공백 없는 긴 URL·경로가 안 접혀 결국 가로로 흐른다.
    func testContentCellsWrap() {
        for html in [unified(), sideBySide()] {
            XCTAssertTrue(html.contains("white-space:pre-wrap"), "pre-wrap이 없다 — 줄이 안 접힌다")
            XCTAssertTrue(html.contains("overflow-wrap:anywhere"), "긴 토큰이 안 접힌다")
        }
        XCTAssertFalse(unified().contains("td.src{white-space:pre;"), "옛 pre 규칙이 남아 있다")
    }

    // MARK: 변경 위치 레일

    /// 레일은 두 뷰 **모두**에 있어야 한다 — 한쪽만 있으면 모드를 바꿀 때 사라진다.
    func testMinimapPresentInBothViews() {
        for (name, html) in [("통합", unified()), ("나란히", sideBySide())] {
            XCTAssertTrue(html.contains("muxa-minimap"), "\(name) 뷰에 변경 위치 레일이 없다")
            XCTAssertTrue(html.contains("MuxaMinimap.watch"), "\(name) 뷰가 레일을 초기화하지 않는다")
        }
    }

    /// 레일 소스는 `Resources/diffdoc/minimap.js` **한 파일**이 단일 출처다 —
    /// 번들에서 못 읽으면 조용히 빈 문자열이 되므로, 실제로 실려 오는지 확인한다.
    func testMinimapSourceIsBundled() {
        XCTAssertNotNil(Bundle.module.url(forResource: "minimap", withExtension: "js", subdirectory: "diffdoc"),
                        "minimap.js가 번들에 없다")
        XCTAssertTrue(unified().contains("MuxaMinimap"), "레일 소스가 인라인되지 않았다(번들 로드 실패)")
    }

    /// 틱 색은 기존 diff 테마를 쓴다 — 레일만 다른 색이면 같은 변경이 두 어휘로 보인다.
    func testMinimapUsesDiffThemeColors() {
        let html = unified()
        XCTAssertTrue(html.contains("#muxa-minimap i.mm-add"))
        XCTAssertTrue(html.contains("#muxa-minimap i.mm-del"))
    }
}
