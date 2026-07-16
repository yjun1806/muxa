import Bonsplit
import XCTest

@testable import muxa

/// AgentRow 순수층 — 긴급도 정렬(그룹 내 안정)·상태 한정 본문·경과 시간 압축.
final class AgentRowTests: XCTestCase {
    private func row(_ state: AgentActivity, title: String = "claude",
                     detail: String? = nil, waiting: TimeInterval? = nil,
                     isAgent: Bool = false, typeIcon: String = "terminal",
                     viewerKind: String? = nil) -> AgentRow {
        AgentRow(tabId: TabID(), title: title, state: state, detail: detail,
                 waitingSeconds: waiting, isAgent: isAgent,
                 typeIcon: typeIcon, viewerKind: viewerKind)
    }

    // MARK: 정렬 — 긴급도 그룹 순서

    func testOrderByUrgencyGroup() {
        let rows = [row(.idle), row(.done), row(.working), row(.waiting)]
        let ordered = AgentRow.ordered(rows)
        XCTAssertEqual(ordered.map(\.state), [.waiting, .working, .done, .idle])
    }

    /// 그룹 내부는 **입력 순서 고정**(안정 정렬) — working 끼리는 넣은 순서 그대로.
    func testStableWithinGroup() {
        let a = row(.working, title: "a")
        let b = row(.working, title: "b")
        let c = row(.working, title: "c")
        let ordered = AgentRow.ordered([c, a, b])
        XCTAssertEqual(ordered.map(\.title), ["c", "a", "b"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue(AgentRow.ordered([]).isEmpty)
    }

    // MARK: 본문 — 상태 인지형

    func testWaitingSubtitleShowsQualifiedTime() {
        XCTAssertEqual(row(.waiting, waiting: 19 * 60).subtitle, "입력 대기 19m째")
    }

    func testWaitingWithoutSecondsFallsBackToLabel() {
        XCTAssertEqual(row(.waiting, waiting: nil).subtitle, AgentActivity.waiting.label)
    }

    func testWorkingSubtitleShowsLiveDetail() {
        XCTAssertEqual(row(.working, detail: "실행 중: swift").subtitle, "실행 중: swift")
    }

    func testWorkingWithoutDetailFallsBackToLabel() {
        XCTAssertEqual(row(.working, detail: nil).subtitle, AgentActivity.working.label)
    }

    /// done엔 상대시간을 붙이지 않는다(벽시계 완료시각 미저장, 계획 #4) — 라벨만.
    func testDoneSubtitleIsPlainLabel() {
        XCTAssertEqual(row(.done, waiting: 9999).subtitle, AgentActivity.done.label)
    }

    /// 뷰어 탭은 상태(유휴)가 아니라 **종류**를 부제로 말한다("파일탭은 파일로").
    func testViewerSubtitleShowsKind() {
        XCTAssertEqual(row(.idle, viewerKind: "문서").subtitle, "문서")
    }

    // MARK: 경과 압축

    func testCompactUnits() {
        XCTAssertEqual(RelativeTime.compact(0), "0s")
        XCTAssertEqual(RelativeTime.compact(45), "45s")
        XCTAssertEqual(RelativeTime.compact(60), "1m")
        XCTAssertEqual(RelativeTime.compact(19 * 60), "19m")
        XCTAssertEqual(RelativeTime.compact(3600), "1h")
        XCTAssertEqual(RelativeTime.compact(86400), "1d")
    }

    func testCompactNegativeClampsToZero() {
        XCTAssertEqual(RelativeTime.compact(-5), "0s")
    }
}
