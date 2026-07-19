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

    /// 이 스냅샷 트리가 참조하는 모든 스크롤백 파일 경로(터미널 탭). 순수 — 스크롤백 GC가
    /// '아직 복원에 필요한 파일'을 고아 판정에서 제외(보존)하는 데 쓴다. lazy 미개방 프로젝트의 파일도 여기로 잡힌다.
    func scrollbackPaths() -> Set<String> {
        switch self {
        case .leaf(let tabs, _, _):
            return Set(tabs.compactMap { $0.scrollbackFile })
        case .split(_, _, let first, let second):
            return first.scrollbackPaths().union(second.scrollbackPaths())
        }
    }

    /// 이 스냅샷 트리의 최상위 탭 개수(터미널+뷰어) — 아직 안 연(lazy) 프로젝트의
    /// 사이드바 "열린 탭 N" 배지가 쓴다(스토어를 만들지 않고 센다 — PTY 스폰 금지).
    func tabCount() -> Int {
        switch self {
        case .leaf(let tabs, _, _):
            return tabs.count
        case .split(_, _, let first, let second):
            return first.tabCount() + second.tabCount()
        }
    }

    /// 이 스냅샷이 참조하는 tmux 세션명 전부(L3 고아 정리의 보존 목록).
    /// **아직 안 연 프로젝트의 세션도 여기 들어와야 한다** — 열린 탭만 세면 lazy 프로젝트의 셸이
    /// 고아로 몰려 죽는다.
    func tmuxSessions() -> Set<String> {
        switch self {
        case .leaf(let tabs, _, _):
            return Set(tabs.compactMap { $0.tmuxSession })
        case .split(_, _, let first, let second):
            return first.tmuxSessions().union(second.tmuxSessions())
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
    // 터미널 탭의 에이전트 재개 바인딩(훅이 넘긴 재개 명령). 옵셔널 — 구 스냅샷엔 없어 하위호환(합성 Codable이
    // 옵셔널을 decodeIfPresent로 처리하므로 구 state.v4.json도 정상 디코드). 복원 시 맵에 되살리기만 하고
    // 실제 재개 실행은 나중 단계가 담당한다.
    var resume: ResumeBinding? = nil
    // 터미널 탭의 화면+스크롤백을 담은 별도 파일 경로(scrollback/<tabId>.txt). 옵셔널 — 구 스냅샷엔 없어
    // 하위호환. 스크롤백 텍스트는 크므로 JSON에 직접 넣지 않고 경로만 저장한다. 복원 시 새 셸에
    // env MUXA_RESTORE_SCROLLBACK_FILE로 주입하면 rc가 이 파일을 cat해 히스토리를 시각 복원한다(④).
    var scrollbackFile: String? = nil
    // 사용자가 손으로 붙인 탭 이름. nil이면 자동 명명(엔진 제목/그룹 종류). 옵셔널 — 구 스냅샷엔 없어 하위호환.
    // 없을 때는 저장은 되면서 복원이 안 돼 재시작마다 이름이 날아갔다.
    var manualTitle: String? = nil
    // 이 탭의 셸이 사는 tmux 세션명(L3). nil이면 일반 셸(tmux 미사용).
    //
    // **세션명을 통째로 저장하는 이유**: 복원 시 tabId가 새로 발급된다(realize → createTab).
    // 세션명을 tabId로 조립하면 재시작 후 자기 세션을 못 찾아 새 셸이 뜨고, 돌던 프로세스는
    // 고아가 된다. 스크롤백이 파일 경로를 저장해 푼 것과 같은 문제다.
    var tmuxSession: String? = nil
}

/// 그룹 서브탭 하나 — 파일이거나 커밋 diff.
struct ItemSnapshot: Codable {
    var file: String?           // 문서/코드/HTML 파일 경로.
    var commit: String?         // 커밋 diff 해시.
    var commitSubject: String?
    // 커밋 **안 파일 하나**의 diff일 때 그 경로(`commit`과 함께 있어야 의미가 있다).
    // 옵셔널 — 구 스냅샷엔 없어 하위호환(합성 Codable이 decodeIfPresent로 처리한다).
    // 없으면 재시작 때 이 서브탭만 통째로 증발한다(복원 분기가 못 알아본다).
    var commitFile: String?
    // 리네임된 파일의 옛 경로 — 없으면 복원된 diff가 빈다.
    var commitFileOldPath: String?
}
