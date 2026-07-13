import Foundation

/// 이 프로세스가 어떤 빌드로 떠 있는지.
///
/// 개발 실행은 `.build/debug/muxa`를 그냥 돌리는 것이라 앱 번들이 아니고, 그래서 bundleIdentifier가 없다
/// (`build-app.sh`로 만든 muxa.app에는 있다). 설치된 앱과 개발 빌드를 나란히 띄워두는 일이 잦으므로
/// **창 제목·메뉴·워드마크가 모두 이 이름을 써서** 어느 창이 어느 빌드인지 헷갈리지 않게 한다.
enum AppInfo {
    static let isDev = Bundle.main.bundleIdentifier == nil
    static let name = isDev ? "muxa (dev)" : "muxa"
}
