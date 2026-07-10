import Foundation

/// 세션 복원용 워크스페이스 레이아웃 — 분할 트리 + 각 탭의 종류·복원 payload를 함께 담는다.
/// cmux 방식: 탭마다 재생성에 필요한 정보(터미널·문서·diff)를 트리에 통째로 저장해
/// '트리=터미널 + 뷰어=별도목록' 2트랙(복원 중 선택이 튀어 빈 터미널을 낳음)을 단일 패스로 대체한다.
/// PTY 내용은 복원 불가 → 터미널은 cwd에서 새 셸. 문서/커밋 diff는 경로/해시로 재생성.
indirect enum PaneSnapshot: Codable {
    case leaf(tabs: [TabSnapshot], selected: Int)
    case split(vertical: Bool, divider: Double, first: PaneSnapshot, second: PaneSnapshot)
}

/// 탭 하나 — `group`이 nil이면 터미널, 아니면 그룹 탭(종류 + 서브탭들).
struct TabSnapshot: Codable {
    var group: String?          // TabGroupKind.raw (documents/html/code/diffs). nil = 터미널.
    var items: [ItemSnapshot]   // 그룹의 서브탭들(터미널이면 빈 배열).
    var selectedItem: Int       // 선택 서브탭 인덱스.
}

/// 그룹 서브탭 하나 — 파일이거나 커밋 diff.
struct ItemSnapshot: Codable {
    var file: String?           // 문서/코드/HTML 파일 경로.
    var commit: String?         // 커밋 diff 해시.
    var commitSubject: String?
}
