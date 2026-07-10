import XCTest
@testable import muxa

/// AttentionLog 시스템 경고 기록(키맵 진단·크래시 복원) 검증 — 전역 컨텍스트 + 제목 기준 dedup.
@MainActor
final class AttentionLogTests: XCTestCase {
    func testRecordSystemAddsGlobalEntry() {
        let log = AttentionLog()
        log.recordSystem(title: "직전에 비정상 종료됐습니다 — 세션을 복원했습니다.")
        XCTAssertEqual(log.entries.count, 1)
        let e = log.entries[0]
        XCTAssertEqual(e.kind, .system)
        // 전역 항목이라 컨텍스트는 비어 있다(클릭 점프 대상 없음 → reveal 안전 무동작).
        XCTAssertEqual(e.projectId, "")
        XCTAssertEqual(e.tabId, "")
        XCTAssertEqual(e.workspaceId, "")
        XCTAssertEqual(log.unreadCount, 1) // 안 읽음으로 뜬다(벨 배지)
    }

    func testRecordSystemDedupsSameMessage() {
        let log = AttentionLog()
        log.recordSystem(title: "같은 경고")
        log.recordSystem(title: "같은 경고") // 라이브 리로드로 동일 진단 재검출 — 중복 안 쌓임
        XCTAssertEqual(log.entries.count, 1)
    }

    func testRecordSystemKeepsDistinctMessages() {
        let log = AttentionLog()
        log.recordSystem(title: "경고 A")
        log.recordSystem(title: "경고 B")
        log.recordSystem(title: "경고 A") // 중간에 B가 껴 있어도 A는 이미 있으니 dedup
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.map(\.title), ["경고 A", "경고 B"])
    }

    func testTabRecordNotDedupedBySystem() {
        // 탭 활동 기록(record)은 서로 다른 종류라 시스템 dedup에 영향받지 않는다.
        let log = AttentionLog()
        log.recordSystem(title: "시스템 경고")
        log.record(workspaceId: "w", projectId: "p", tabId: "t", kind: .done, title: "완료")
        XCTAssertEqual(log.entries.count, 2)
    }
}
