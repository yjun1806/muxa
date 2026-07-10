import Foundation

/// 세션 복원용 워크스페이스 레이아웃 — 분할 트리 + 각 탭의 종류·복원 payload를 함께 담는다.
/// cmux 방식: 탭마다 재생성에 필요한 정보(터미널·문서·diff)를 트리에 통째로 저장해
/// '트리=터미널 + 뷰어=별도목록' 2트랙(복원 중 선택이 튀어 빈 터미널을 낳음)을 단일 패스로 대체한다.
/// PTY 내용은 복원 불가 → 터미널은 cwd에서 새 셸. 문서/커밋 diff는 경로/해시로 재생성.
indirect enum PaneSnapshot: Codable {
    /// `focused`=이 리프가 저장 시점의 활성(focused) 칸이었는지. 복원 후 전역 포커스를 여기로 되돌린다.
    case leaf(tabs: [TabSnapshot], selected: Int, focused: Bool)
    case split(vertical: Bool, divider: Double, first: PaneSnapshot, second: PaneSnapshot)

    // 커스텀 Codable — `focused`는 나중에 추가된 필드라 decodeIfPresent로 하위호환(구 state.v4.json엔 없음).
    // 인코딩 형식은 Swift가 열거형에 합성하던 것과 동일(케이스명 키 → 연관값 라벨 키)이라 구 데이터도 그대로 읽힌다.
    private enum CaseKey: String, CodingKey { case leaf, split }
    private enum LeafKey: String, CodingKey { case tabs, selected, focused }
    private enum SplitKey: String, CodingKey { case vertical, divider, first, second }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if c.contains(.leaf) {
            let l = try c.nestedContainer(keyedBy: LeafKey.self, forKey: .leaf)
            self = .leaf(
                tabs: try l.decode([TabSnapshot].self, forKey: .tabs),
                selected: try l.decode(Int.self, forKey: .selected),
                focused: try l.decodeIfPresent(Bool.self, forKey: .focused) ?? false
            )
        } else if c.contains(.split) {
            let s = try c.nestedContainer(keyedBy: SplitKey.self, forKey: .split)
            self = .split(
                vertical: try s.decode(Bool.self, forKey: .vertical),
                divider: try s.decode(Double.self, forKey: .divider),
                first: try s.decode(PaneSnapshot.self, forKey: .first),
                second: try s.decode(PaneSnapshot.self, forKey: .second)
            )
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "알 수 없는 PaneSnapshot 케이스"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .leaf(let tabs, let selected, let focused):
            var l = c.nestedContainer(keyedBy: LeafKey.self, forKey: .leaf)
            try l.encode(tabs, forKey: .tabs)
            try l.encode(selected, forKey: .selected)
            try l.encode(focused, forKey: .focused)
        case .split(let vertical, let divider, let first, let second):
            var s = c.nestedContainer(keyedBy: SplitKey.self, forKey: .split)
            try s.encode(vertical, forKey: .vertical)
            try s.encode(divider, forKey: .divider)
            try s.encode(first, forKey: .first)
            try s.encode(second, forKey: .second)
        }
    }
}

/// 탭 하나 — `group`이 nil이면 터미널, 아니면 그룹 탭(종류 + 서브탭들).
struct TabSnapshot: Codable {
    var group: String?          // TabGroupKind.raw (documents/html/code/diffs). nil = 터미널.
    var items: [ItemSnapshot]   // 그룹의 서브탭들(터미널이면 빈 배열).
    var selectedItem: Int       // 선택 서브탭 인덱스.
    // 터미널 탭의 마지막 작업 디렉터리(OSC 7). 옵셔널 — 구 스냅샷엔 없어 decodeIfPresent로 하위호환.
    // 복원 시 이 경로에서 새 셸을 띄운다. nil이면 워크스페이스 기본 cwd.
    var cwd: String? = nil
}

/// 그룹 서브탭 하나 — 파일이거나 커밋 diff.
struct ItemSnapshot: Codable {
    var file: String?           // 문서/코드/HTML 파일 경로.
    var commit: String?         // 커밋 diff 해시.
    var commitSubject: String?
}
