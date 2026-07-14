import Foundation

/// 사용자가 문제를 보고할 때 붙일 **진단 정보** — 값 주입 순수 조립(부작용은 호출부: 클립보드·Finder).
///
/// 지금까지 사용자가 "가끔 터진다"고 말해도 개발자가 받을 자료가 없었다(로그 파일도, 내보내기 동선도 없다).
/// 계정 없이 가능한 최소 동선부터: 앱 메뉴의 "진단 정보 복사" + "지원 폴더 열기".
enum Diagnostics {
    /// 붙여넣기 좋은 한 덩어리 텍스트. 값은 전부 주입받는다(테스트 가능).
    static func report(name: String, version: String, build: String, os: String,
                       supportDir: String, lastLaunchWasDirty: Bool) -> String {
        [
            "muxa 진단 정보",
            "앱: \(name) \(version) (\(build))",
            "macOS: \(os)",
            "지원 폴더: \(supportDir)",
            "직전 종료: \(lastLaunchWasDirty ? "비정상(크래시·강제종료)" : "정상")",
        ].joined(separator: "\n")
    }
}
