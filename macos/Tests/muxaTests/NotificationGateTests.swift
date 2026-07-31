import Testing
@testable import muxa

/// NotificationGate 순수 배달 결정 테이블 검증.
struct NotificationGateTests {
    @Test func visibleIdleReminderSuppressed() {
        #expect(NotificationGate.shouldDeliver(category: .idleReminder, isVisibleToUser: true) == .suppressed)
    }

    @Test func visibleAllSuppressed() {
        // 보이는 칸은 전부 억제 — 상태 테두리가 이미 상태를 말한다(플래시 채널 제거).
        #expect(NotificationGate.shouldDeliver(category: .needsPermission, isVisibleToUser: true) == .suppressed)
        #expect(NotificationGate.shouldDeliver(category: .turnComplete, isVisibleToUser: true) == .suppressed)
        #expect(NotificationGate.shouldDeliver(category: nil, isVisibleToUser: true) == .suppressed)
    }

    @Test func hiddenIdleReminderBadgeOnly() {
        #expect(NotificationGate.shouldDeliver(category: .idleReminder, isVisibleToUser: false) == .badgeOnly)
    }

    @Test func hiddenUrgentBadgeAndNotify() {
        #expect(NotificationGate.shouldDeliver(category: .needsPermission, isVisibleToUser: false) == .badgeAndNotify)
        #expect(NotificationGate.shouldDeliver(category: .turnComplete, isVisibleToUser: false) == .badgeAndNotify)
    }

    @Test func hiddenNilCategoryPreservesLegacyBehavior() {
        // category == nil(자동 신호)은 안 보이면 배지+시스템 알림(기존 동작 보존).
        #expect(NotificationGate.shouldDeliver(category: nil, isVisibleToUser: false) == .badgeAndNotify)
    }

    @Test func categoryRawValues() {
        #expect(NotifyCategory(rawValue: "needs-permission") == .needsPermission)
        #expect(NotifyCategory(rawValue: "turn-complete") == .turnComplete)
        #expect(NotifyCategory(rawValue: "idle-reminder") == .idleReminder)
        #expect(NotifyCategory(rawValue: "bogus") == nil)
    }
}
