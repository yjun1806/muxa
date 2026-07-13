import Foundation

/// muxa의 Application Support 베이스 디렉터리(`~/Library/Application Support/muxa`).
/// 세션 상태(state.v4.json)·스크롤백·크래시 마커가 공유하는 단일 경로 소유자 —
/// 같은 경로 계산을 여러 곳에 흩뿌리지 않는다. 최초 접근 시 디렉터리를 만든다.
///
/// **개발 빌드는 워크트리마다 따로 쓴다**(`muxa-dev-<워크트리>-<해시>`). 워크트리마다 개발빌드를
/// 띄우는 게 일상인데 저장소를 공유하면 서로의 세션을 덮어쓴다 — 실제로 그렇게 터졌다(AppInfo.devKey).
/// 릴리스는 격리하지 않는다(사용자 데이터는 하나뿐이다).
enum MuxaSupportDir {
    /// 저장소 디렉터리 이름 — 릴리스는 `muxa`, 개발 빌드는 워크트리별로 갈린다.
    static let folderName: String = {
        guard let key = AppInfo.devKey else { return "muxa" }
        return "muxa-dev-\(key)"
    }()

    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// muxa 베이스 아래 하위 디렉터리(없으면 생성).
    static func subdirectory(_ name: String) -> URL {
        let dir = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
