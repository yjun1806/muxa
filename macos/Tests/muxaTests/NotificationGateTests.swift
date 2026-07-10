import XCTest
@testable import muxa

/// NotificationGate 순수 배달 결정 테이블 검증.
final class NotificationGateTests: XCTestCase {
    func testVisibleIdleReminderSuppressed() {
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .idleReminder, isVisibleToUser: true), .suppressed)
    }

    func testVisibleOtherFlashOnly() {
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .needsPermission, isVisibleToUser: true), .flashOnly)
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .turnComplete, isVisibleToUser: true), .flashOnly)
        XCTAssertEqual(NotificationGate.shouldDeliver(category: nil, isVisibleToUser: true), .flashOnly)
    }

    func testHiddenIdleReminderBadgeOnly() {
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .idleReminder, isVisibleToUser: false), .badgeOnly)
    }

    func testHiddenUrgentBadgeAndNotify() {
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .needsPermission, isVisibleToUser: false), .badgeAndNotify)
        XCTAssertEqual(NotificationGate.shouldDeliver(category: .turnComplete, isVisibleToUser: false), .badgeAndNotify)
    }

    func testHiddenNilCategoryPreservesLegacyBehavior() {
        // category == nil(자동 신호)은 안 보이면 배지+시스템 알림(기존 동작 보존).
        XCTAssertEqual(NotificationGate.shouldDeliver(category: nil, isVisibleToUser: false), .badgeAndNotify)
    }

    func testCategoryRawValues() {
        XCTAssertEqual(NotifyCategory(rawValue: "needs-permission"), .needsPermission)
        XCTAssertEqual(NotifyCategory(rawValue: "turn-complete"), .turnComplete)
        XCTAssertEqual(NotifyCategory(rawValue: "idle-reminder"), .idleReminder)
        XCTAssertNil(NotifyCategory(rawValue: "bogus"))
    }
}
