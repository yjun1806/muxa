import AppKit
import UserNotifications

/// 데스크톱 알림에 실어 보내는 라우팅 컨텍스트(워크스페이스·프로젝트·탭).
/// 알림을 클릭하면 이 값으로 "그 탭이 있던 프로젝트"까지 되짚어 활성화한다.
struct NotifyContext {
    let workspaceId: String
    let projectId: String
    let tabId: String
}

/// macOS 알림 래퍼 — 데스크톱 알림(OSC 9/777·훅)을 UNUserNotificationCenter로 띄우고,
/// 클릭 시 컨텍스트로 원클릭 검토 동선(프로젝트 활성 + Git 패널)을 연다.
///
/// 앱 번들(.app) 없이 실행하면(bare `.build/debug/muxa`) UNUserNotificationCenter가 무동작/크래시하므로
/// bundleIdentifier로 가드하고, 번들이 아니면 Dock 바운스(requestUserAttention)로 폴백한다.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// userInfo 키 — 알림에 실어 보낸 라우팅 컨텍스트를 되읽는다.
    private enum Key {
        static let workspaceId = "muxa.workspaceId"
        static let projectId = "muxa.projectId"
        static let tabId = "muxa.tabId"
    }

    /// .app 번들에서 실행 중인지 — UNUserNotificationCenter 사용 가능 조건.
    private let bundled = Bundle.main.bundleIdentifier != nil
    private var authorized = false
    /// 사용자가 알림을 **거부**했는가(.denied). 거부는 조용한 Dock 바운스 폴백으로 끝나 사용자가
    /// "알림 기능이 고장났다"고 믿게 된다 — 상위(AppState)가 인박스에 표면화하도록 알린다.
    private(set) var denied = false

    /// 알림 클릭 라우팅 — AppDelegate가 AppState.revealActivity로 주입한다(경계 밖 부작용을 상위가 소유).
    var onActivate: ((NotifyContext) -> Void)?
    /// 알림이 꺼져 있음을 표면화하는 콜백(부작용 소유는 상위). refreshAuthorization이 .denied를 볼 때마다 호출 — dedup은 AttentionLog.
    var onDenied: (() -> Void)?

    private override init() { super.init() }

    /// 앱 시작 시 1회 — delegate 등록 + 알림 권한 요청. 번들이 아니면 무동작(배지만 동작).
    func requestAuthorizationIfPossible() {
        guard bundled else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            // granted 하나만 믿지 않는다 — 이미 거부된 상태면 프롬프트가 다시 안 뜨고 콜백만 false로 온다.
            // 실제 상태(.denied 포함)는 시스템에 되묻는다.
            Task { @MainActor in self?.refreshAuthorization() }
        }
    }

    /// 알림 권한 상태를 **시스템에서 다시 읽는다**. 앱 활성화 때마다 부른다(AppDelegate).
    ///
    /// 시작 시 requestAuthorization 콜백 한 번으로 캐시하면, 사용자가 나중에 시스템 설정에서 켜도
    /// 앱은 그 세션 내내 false로 믿어 알림이 안 온다.
    func refreshAuthorization() {
        guard bundled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                guard let self else { return }
                self.authorized = status == .authorized || status == .provisional
                self.denied = status == .denied
                if self.denied { self.onDenied?() }
            }
        }
    }

    /// 데스크톱 알림 표시. 번들+승인이면 시스템 알림(컨텍스트를 userInfo로 실어 클릭 라우팅 가능),
    /// 아니면 Dock 아이콘 바운스로 대체.
    func notify(title: String, body: String, context: NotifyContext? = nil) {
        guard bundled, authorized else {
            NSApp.requestUserAttention(.informationalRequest) // Dock 바운스 폴백
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "muxa" : title
        content.body = body
        if let context {
            content.userInfo = [
                Key.workspaceId: context.workspaceId,
                Key.projectId: context.projectId,
                Key.tabId: context.tabId,
            ]
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// 앱이 포그라운드여도 배너로 표시(다른 칸을 보는 중일 수 있으므로).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 알림 클릭 → userInfo에서 컨텍스트를 되읽어 라우팅 콜백 호출(프로젝트 활성 + Git 패널).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let context = Self.context(from: userInfo) { self.onActivate?(context) }
            completionHandler()
        }
    }

    /// userInfo → NotifyContext. projectId가 없으면 라우팅 불가로 nil.
    private static func context(from userInfo: [AnyHashable: Any]) -> NotifyContext? {
        guard let projectId = userInfo[Key.projectId] as? String, !projectId.isEmpty else { return nil }
        return NotifyContext(
            workspaceId: userInfo[Key.workspaceId] as? String ?? "",
            projectId: projectId,
            tabId: userInfo[Key.tabId] as? String ?? ""
        )
    }
}
