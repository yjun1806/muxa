import Foundation

/// 이 프로세스가 어떤 빌드로 떠 있는지.
///
/// 워크트리마다 개발빌드를 띄우는 게 일상이라 **"muxa"가 여러 개 뜬다** — Dock·⌘Tab·창 제목이 전부
/// 똑같으면 어느 창이 어느 브랜치인지 알 수 없다. 그래서 `build-app.sh`가 개발 번들에는 브랜치(또는
/// 워크트리) 이름을 `CFBundleName`에 박고(`muxa · session-restore`), 여기서 그 이름을 읽어
/// 창 제목·메뉴·워드마크가 모두 같은 이름을 쓰게 한다.
///
/// bare 실행(`.build/debug/muxa` 직접)은 번들이 아니라 이름을 못 박는다 — Dock에 프로세스명("muxa")으로
/// 뜨고 시스템 알림도 못 쓴다. 그래서 여러 개발빌드를 구분해 띄우려면 **`build-app.sh`로 번들을 만들어야**
/// 한다(`open macos/.build/debug/muxa-<브랜치>.app`).
enum AppInfo {
    /// 앱 번들이 아니면(=bare 실행) 개발 실행이다. 번들 개발빌드는 id가 `com.muxa.dev.*`다.
    static let isDev = bundleId == nil || bundleId?.hasPrefix(devBundlePrefix) == true

    /// 표시 이름 — 번들이면 CFBundleName(개발빌드는 브랜치명 포함), bare면 "muxa (dev)".
    static let name: String = {
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty { return bundleName }
        return "muxa (dev)"
    }()

    private static let bundleId = Bundle.main.bundleIdentifier
    private static let devBundlePrefix = "com.muxa.dev."
}
