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

    // MARK: 덩어리 나누기 — 터미널 / 뷰어

    /// 터미널(상태가 변하는 것)과 뷰어(참고하는 것)를 가른다. **각 덩어리 안의 순서는 입력 그대로**
    /// (입력은 이미 `ordered`를 거친 긴급도순 — 여기서 다시 흔들면 클릭 대상이 움직인다).
    func testSectionsSplitTerminalsFromViewers() {
        let rows = [row(.waiting, title: "claude"),
                    row(.idle, title: "ARCHITECTURE.md", viewerKind: "문서"),
                    row(.working, title: "swift build"),
                    row(.idle, title: "변경 4", viewerKind: "변경")]
        let s = AgentRow.sections(rows)
        XCTAssertEqual(s.terminals.map(\.title), ["claude", "swift build"])
        XCTAssertEqual(s.viewers.map(\.title), ["ARCHITECTURE.md", "변경 4"])
    }

    /// 유휴 **터미널**만 접힌다 — 뷰어는 영원히 유휴라 접으면 아무것도 안 남는다("파일탭은 파일로").
    func testSectionsFoldIdleTerminalsOnly() {
        let rows = [row(.working, title: "swift build"),
                    row(.idle, title: "zsh"),
                    row(.idle, title: "zsh2"),
                    row(.idle, title: "DESIGN.md", viewerKind: "문서")]
        let s = AgentRow.sections(rows)
        XCTAssertEqual(s.terminals.map(\.title), ["swift build"])
        XCTAssertEqual(s.idleTerminals, 2)
        XCTAssertEqual(s.viewers.map(\.title), ["DESIGN.md"])
    }

    /// 구분선은 **양쪽이 다 있을 때만**. 뷰어 0개가 가장 흔한 경우고, 그때는 지금과 똑같이 보여야 한다.
    func testSeparatorHiddenWithoutViewers() {
        let s = AgentRow.sections([row(.working), row(.idle)])
        XCTAssertFalse(s.showsSeparator)
    }

    /// 터미널이 하나도 없으면(문서만 열어둔 프로젝트) 선 위가 비어 상단 여백이 어긋난다 — 안 그린다.
    func testSeparatorHiddenWithoutTerminals() {
        let s = AgentRow.sections([row(.idle, title: "DESIGN.md", viewerKind: "문서")])
        XCTAssertFalse(s.showsSeparator)
    }

    /// 터미널이 전부 유휴여도 "유휴 N" 폴드 행이 선 위에 남는다 — 그러니 선을 그린다.
    func testSeparatorShownWhenOnlyIdleTerminalsRemain() {
        let s = AgentRow.sections([row(.idle, title: "zsh"),
                                   row(.idle, title: "DESIGN.md", viewerKind: "문서")])
        XCTAssertTrue(s.terminals.isEmpty)
        XCTAssertEqual(s.idleTerminals, 1)
        XCTAssertTrue(s.showsSeparator)
    }

    func testSectionsOfEmptyDrawsNothing() {
        let s = AgentRow.sections([])
        XCTAssertTrue(s.terminals.isEmpty)
        XCTAssertTrue(s.viewers.isEmpty)
        XCTAssertEqual(s.idleTerminals, 0)
        XCTAssertFalse(s.showsSeparator)
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

    // MARK: 목록 행 두 열(L1) — 본문(bodyLabel) ⟂ 시간(timeLabel)

    /// 대기 행은 본문("입력 대기")과 시간("19m")이 **두 열로 갈린다** — 시간은 우측 열이 맡는다.
    func testWaitingSplitsBodyAndTime() {
        let r = row(.waiting, waiting: 19 * 60)
        XCTAssertEqual(r.bodyLabel, AgentActivity.waiting.label)
        XCTAssertEqual(r.timeLabel, "19m")
    }

    /// 시간 열은 **대기 경과만** — working/done/idle은 시각 미저장이라 nil(지어내지 않는다).
    func testTimeLabelOnlyForWaiting() {
        XCTAssertNil(row(.working, detail: "실행 중: swift").timeLabel)
        XCTAssertNil(row(.done, waiting: 9999).timeLabel)
        XCTAssertNil(row(.idle).timeLabel)
        XCTAssertNil(row(.waiting, waiting: nil).timeLabel) // 경과를 모르면 침묵
    }

    /// 본문 열은 시간을 뺀 subtitle과 같다 — 작업=라이브 도구, 뷰어=종류.
    func testBodyLabelMatchesSubtitleSansTime() {
        XCTAssertEqual(row(.working, detail: "실행 중: swift").bodyLabel, "실행 중: swift")
        XCTAssertEqual(row(.idle, viewerKind: "문서").bodyLabel, "문서")
        XCTAssertEqual(row(.done).bodyLabel, AgentActivity.done.label)
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
