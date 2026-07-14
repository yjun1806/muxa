import Foundation

/// 첫 워크스페이스(저장된 세션이 없는 첫 실행) 경로 판정 — 순수 함수.
///
/// **왜 프로세스 cwd를 그냥 쓰면 안 되나**: `.app`을 Finder·Dock에서 열면 launchd가 띄우므로
/// cwd가 `/`다. 그걸 첫 워크스페이스 경로로 쓰면 상용 앱의 첫 화면이 **파일시스템 루트**가 된다
/// (익스플로러에 /System·/Volumes가 뜨고, git 패널은 "저장소 아님"). 터미널에서 `swift build` 후
/// 실행하는 개발 빌드는 cwd가 리포라 아무도 못 본다 — CLAUDE.md가 경고한 그 함정이다.
///
/// cwd가 의미 있는 건 **CLI로 띄운 bare 개발 빌드**뿐이므로, 번들이면(=사용자가 여는 앱) 홈으로 간다.
enum InitialWorkspacePath {
    /// 설정값 > (bare 개발 실행일 때만) 현재 디렉터리 > 홈.
    /// - Parameters:
    ///   - configured: `default_workspace_path` 설정(없으면 nil)
    ///   - currentDir: 프로세스 cwd
    ///   - isBundled: `.app` 번들로 실행 중인가(= Bundle.main.bundleIdentifier != nil)
    static func resolve(configured: String?, currentDir: String?, isBundled: Bool, home: String) -> String {
        if let configured, !configured.isEmpty { return configured }
        // 루트(`/`)는 cwd로도 배제한다 — CLI로 `/`에서 띄웠다 해도 첫 화면이 파일시스템 루트일 이유는 없다.
        if !isBundled, let currentDir, currentDir != "/", !currentDir.isEmpty { return currentDir }
        return home
    }
}
