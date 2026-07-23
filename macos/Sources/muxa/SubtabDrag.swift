import Bonsplit
import Foundation

/// 서브탭 드래그의 페이로드 규약 — Bonsplit 드롭존은 `.fileURL`만 받으므로, 파일 URL을 "입장권"으로
/// 함께 싣되 **진짜 이동 대상은 이 타입**으로 나른다. 경로가 아니라 (원본 그룹 탭, 서브탭 id)를 실어
/// 드롭 시 실제 `GroupItemContent`를 그대로 옮긴다(diff·뷰어 종류를 잃지 않는다).
enum SubtabDrag {
    /// 드래그 pasteboard에 싣는 커스텀 타입 식별자.
    static let typeId = "com.muxa.subtab"

    struct Payload: Codable, Equatable {
        let sourceTab: TabID
        let itemId: String
    }
}
