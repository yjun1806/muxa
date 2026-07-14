import Foundation

/// 프로젝트/워크스페이스 경로가 **아직 쓸 수 있는 폴더인가** — 순수 판정(FileManager 주입).
///
/// 폴더가 사라지거나(이름 변경·삭제·외장 디스크 언마운트) 권한이 없으면(TCC 거부) 그 사실이
/// 각 패널에서 **서로 다른 거짓말**로 나타난다: Git 패널은 "git 저장소 아님", 익스플로러는 빈 트리,
/// 서비스는 회색 점. 진짜 원인을 먼저 판정해 그대로 말한다.
enum PathState: Equatable {
    case ok
    /// 폴더가 없다(삭제·이름 변경·언마운트).
    case missing
    /// 폴더는 있는데 읽을 수 없다(권한·TCC 거부).
    case denied

    static func check(_ path: String, fileManager: FileManager = .default) -> PathState {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return .missing }
        return fileManager.isReadableFile(atPath: path) ? .ok : .denied
    }

    /// 사용자에게 보일 사유. 정상이면 nil.
    var message: String? {
        switch self {
        case .ok: return nil
        case .missing: return "폴더를 찾을 수 없습니다"
        case .denied: return "폴더에 접근할 수 없습니다 (권한)"
        }
    }
}
