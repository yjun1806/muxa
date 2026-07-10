import Foundation

/// muxa의 Application Support 베이스 디렉터리(`~/Library/Application Support/muxa`).
/// 세션 상태(state.v4.json)·스크롤백·크래시 마커가 공유하는 단일 경로 소유자 —
/// 같은 경로 계산을 여러 곳에 흩뿌리지 않는다. 최초 접근 시 디렉터리를 만든다.
enum MuxaSupportDir {
    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
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
