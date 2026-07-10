import AppKit
import UserNotifications

/// macOS 알림 래퍼 — 데스크톱 알림(OSC 9/777)을 UNUserNotificationCenter로 띄운다.
/// 앱 번들(.app) 없이 실행하면(bare `.build/debug/muxa`) UNUserNotificationCenter가 무동작/크래시하므로
/// bundleIdentifier로 가드하고, 번들이 아니면 Dock 바운스(requestUserAttention)로 폴백한다.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// .app 번들에서 실행 중인지 — UNUserNotificationCenter 사용 가능 조건.
    private let bundled = Bundle.main.bundleIdentifier != nil
    private var authorized = false

    private init() {}

    /// 앱 시작 시 1회 — 알림 권한 요청. 번들이 아니면 무동작(배지만 동작).
    func requestAuthorizationIfPossible() {
        guard bundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// 데스크톱 알림 표시. 번들+승인이면 시스템 알림, 아니면 Dock 아이콘 바운스로 대체.
    func notify(title: String, body: String) {
        guard bundled, authorized else {
            NSApp.requestUserAttention(.informationalRequest) // Dock 바운스 폴백
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "muxa" : title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
