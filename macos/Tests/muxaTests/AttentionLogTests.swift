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

/// 알림 종류·카테고리 → 상태 톤 매핑 — 인박스가 사이드바·탭과 **같은 어휘**를 쓰는지 못박는다.
/// 한때 인박스만 자체 아이콘 표(완료=git 초록 checkmark.circle.fill)를 들고 있어 같은 사건이
/// 화면 위치마다 다르게 보였다. 렌더는 StatusStyle이 이 톤에서 파생하므로 여기만 지키면 어휘가 하나로 남는다.
@MainActor
final class AttentionToneTests: XCTestCase {
    func test훅_카테고리가_대기와_완료를_가른다() {
        // 둘 다 kind는 .notify다 — category만이 유일한 구분 근거다(이게 유실되면 인박스는 "뭔가 왔다"까지만 말한다).
        XCTAssertEqual(AttentionKind.notify.tone(category: .needsPermission), .attention)
        XCTAssertEqual(AttentionKind.notify.tone(category: .turnComplete), .success)
        XCTAssertEqual(AttentionKind.notify.tone(category: .idleReminder), .quiet)
    }

    func test자동신호는_부른_쪽으로_본다() {
        // OSC 9/777은 category가 없다 — 무슨 일인지 모르므로 조용히 넘기지 않는다.
        XCTAssertEqual(AttentionKind.notify.tone(category: nil), .attention)
    }

    func test카테고리없는_종류는_자기_의미를_따른다() {
        XCTAssertEqual(AttentionKind.done.tone(category: nil), .success)
        XCTAssertEqual(AttentionKind.system.tone(category: nil), .failure)
        XCTAssertEqual(AttentionKind.bell.tone(category: nil), .attention)
    }

    func test기록된_엔트리가_톤을_보존한다() {
        // category는 발사 순간에만 있다 — 인박스는 나중에 그리므로 엔트리가 톤을 들고 있어야 한다.
        let log = AttentionLog()
        log.record(workspaceId: "w", projectId: "p", tabId: "t",
                   kind: .notify, tone: .attention, title: "승인 필요")
        XCTAssertEqual(log.entries.last?.tone, .attention)
    }

    func test시스템경고는_실패톤이다() {
        let log = AttentionLog()
        log.recordSystem(title: "키맵 충돌")
        XCTAssertEqual(log.entries.last?.tone, .failure)
    }
}
